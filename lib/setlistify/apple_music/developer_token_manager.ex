defmodule Setlistify.AppleMusic.DeveloperTokenManager do
  @moduledoc """
  Singleton GenServer that generates and caches the Apple Music developer token.

  Unlike user tokens, the developer token is not tied to any individual user — it
  identifies the app itself to Apple's API and is shared across all requests. Apple
  issues developer tokens as ES256-signed JWTs with a maximum lifetime of 180 days,
  though we sign ours for 30 days.

  Because the token must be present before any Apple Music API call can succeed, this
  process generates the token eagerly on startup (via `handle_continue`) rather than
  lazily on first call. When configuration is valid, callers are guaranteed to receive
  a non-nil token even on the very first `get_token/0` call.

  ## Rotation

  The token is automatically rotated 5 minutes before it expires. A `Process.send_after`
  timer fires a `:refresh_token` message, which regenerates and caches a fresh token
  before the old one becomes invalid. This means callers never need to think about
  expiry — `get_token/0` always returns a valid token.

  ## Degraded mode

  If token generation fails (misconfigured PEM, missing env vars, etc.) the process
  does **not** crash. It logs a stacktraced error plus a human-readable banner
  ("Apple Music sign-in is DISABLED"), keeps `token: nil` in state, and schedules
  a retry on an exponential backoff (base 30s, capped at 15m by default). Callers
  receive `nil` from `get_token/0` (the layout's existing guard hides the sign-in
  UI). The backoff means a long-lived misconfig produces a handful of stacktraces
  per hour rather than one every 5 minutes, while still surfacing the failure
  promptly when it first occurs. The schedule resets to the base interval on
  successful recovery or on `regenerate_token/0`.

  If the cached token's `expires_at` passes while the manager is stuck retrying
  (e.g. signing has been broken for the token's whole 30-day lifetime),
  `get_token/0` returns `nil` rather than handing back an expired binary.

  ## Telemetry

  Each attempt emits `[:setlistify, :apple_music, :developer_token, :attempt]`
  with measurements `%{count: 1, healthy: 1 | 0}` and metadata
  `%{phase: :generate | :refresh | :regenerate | :retry, outcome: :ok | :error}`.
  `Setlistify.PromEx.Plugins.AppleMusic` derives a counter (by phase × outcome)
  and a "last attempt healthy" gauge from this event.
  """

  use GenServer

  alias __MODULE__.State

  require Logger

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            token: String.t() | nil,
            expires_at: integer() | nil,
            timer_ref: reference() | nil,
            retry_base_ms: pos_integer(),
            retry_max_ms: pos_integer(),
            retry_multiplier: pos_integer(),
            current_retry_ms: pos_integer()
          }

    @enforce_keys [:retry_base_ms, :retry_max_ms, :retry_multiplier, :current_retry_ms]
    defstruct [
      :token,
      :expires_at,
      :timer_ref,
      :retry_base_ms,
      :retry_max_ms,
      :retry_multiplier,
      :current_retry_ms
    ]
  end

  @telemetry_event [:setlistify, :apple_music, :developer_token, :attempt]

  @refresh_threshold 5 * 60
  @default_ttl_seconds 30 * 24 * 60 * 60
  @default_retry_base_ms 30 * 1_000
  @default_retry_max_ms 15 * 60 * 1_000
  @default_retry_multiplier 2

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Returns the cached developer token, or `nil` if generation has failed or the token has expired."
  def get_token, do: GenServer.call(__MODULE__, :get_token)

  @doc """
  Forces immediate token regeneration and returns the new token.
  Called on a 401 response from ExternalClient. Cancels the pending scheduled
  refresh and reschedules from the new expiry to prevent a double refresh.

  Resets the retry backoff to its base interval regardless of outcome — an
  operator-initiated call deserves a fresh schedule. Returns the existing cached
  token (which may be `nil` in degraded mode) if regeneration fails.
  """
  def regenerate_token, do: GenServer.call(__MODULE__, :regenerate_token)

  @doc "The telemetry event name emitted on each token attempt."
  def telemetry_event, do: @telemetry_event

  def init(opts) do
    retry_base_ms = retry_opt(opts, :retry_base_ms, :apple_music_retry_base_ms, @default_retry_base_ms)
    retry_max_ms = retry_opt(opts, :retry_max_ms, :apple_music_retry_max_ms, @default_retry_max_ms)

    retry_multiplier =
      retry_opt(opts, :retry_multiplier, :apple_music_retry_multiplier, @default_retry_multiplier)

    state = %State{
      retry_base_ms: retry_base_ms,
      retry_max_ms: retry_max_ms,
      retry_multiplier: retry_multiplier,
      current_retry_ms: retry_base_ms
    }

    {:ok, state, {:continue, :generate_token}}
  end

  def handle_continue(:generate_token, %State{} = state) do
    case generate_and_sign() do
      {:ok, token, expires_at} ->
        emit_attempt(:generate, :ok)
        timer_ref = schedule_refresh(expires_at, state.timer_ref)

        {:noreply,
         %{
           state
           | token: token,
             expires_at: expires_at,
             timer_ref: timer_ref,
             current_retry_ms: state.retry_base_ms
         }}

      {:error, reason} ->
        log_token_error(:generate, reason)
        emit_attempt(:generate, :error)
        {timer_ref, next_retry_ms} = schedule_retry(state)

        {:noreply,
         %{
           state
           | token: nil,
             expires_at: nil,
             timer_ref: timer_ref,
             current_retry_ms: next_retry_ms
         }}
    end
  end

  def handle_call(:get_token, _from, %State{} = state) do
    if expired?(state) do
      {:reply, nil, %{state | token: nil, expires_at: nil}}
    else
      {:reply, state.token, state}
    end
  end

  def handle_call(:regenerate_token, _from, %State{} = state) do
    state = %{state | current_retry_ms: state.retry_base_ms}

    case generate_and_sign() do
      {:ok, token, expires_at} ->
        emit_attempt(:regenerate, :ok)
        timer_ref = schedule_refresh(expires_at, state.timer_ref)
        {:reply, token, %{state | token: token, expires_at: expires_at, timer_ref: timer_ref}}

      {:error, reason} ->
        log_token_error(:regenerate, reason)
        emit_attempt(:regenerate, :error)
        {:reply, state.token, state}
    end
  end

  def handle_info(:refresh_token, %State{} = state) do
    case generate_and_sign() do
      {:ok, token, expires_at} ->
        emit_attempt(:refresh, :ok)
        timer_ref = schedule_refresh(expires_at, state.timer_ref)

        {:noreply,
         %{
           state
           | token: token,
             expires_at: expires_at,
             timer_ref: timer_ref,
             current_retry_ms: state.retry_base_ms
         }}

      {:error, reason} ->
        log_token_error(:refresh, reason)
        emit_attempt(:refresh, :error)
        {timer_ref, next_retry_ms} = schedule_retry(state)
        {:noreply, %{state | timer_ref: timer_ref, current_retry_ms: next_retry_ms}}
    end
  end

  def handle_info(:retry_generate, %State{} = state) do
    case generate_and_sign() do
      {:ok, token, expires_at} ->
        Logger.info("Apple Music developer token recovered after earlier failure")
        emit_attempt(:retry, :ok)
        timer_ref = schedule_refresh(expires_at, state.timer_ref)

        {:noreply,
         %{
           state
           | token: token,
             expires_at: expires_at,
             timer_ref: timer_ref,
             current_retry_ms: state.retry_base_ms
         }}

      {:error, reason} ->
        log_token_error(:retry, reason)
        emit_attempt(:retry, :error)
        {timer_ref, next_retry_ms} = schedule_retry(state)
        {:noreply, %{state | timer_ref: timer_ref, current_retry_ms: next_retry_ms}}
    end
  end

  defp expired?(%State{token: token, expires_at: expires_at}) when is_binary(token) and is_integer(expires_at) do
    expires_at <= System.system_time(:second)
  end

  defp expired?(%State{}), do: false

  defp generate_and_sign do
    now = System.system_time(:second)
    expires_at = now + @default_ttl_seconds
    team_id = Application.fetch_env!(:setlistify, :apple_music_team_id)
    key_id = Application.fetch_env!(:setlistify, :apple_music_key_id)
    pem = Application.fetch_env!(:setlistify, :apple_music_private_key)

    token =
      Setlistify.AppleMusic.JWT.sign(%{"iat" => now, "exp" => expires_at}, pem, key_id, team_id)

    {:ok, token, expires_at}
  rescue
    e -> {:error, {e, __STACKTRACE__}}
  end

  defp log_token_error(phase, {exception, stacktrace}) when phase in [:generate, :refresh, :regenerate, :retry] do
    Logger.error("""
    Apple Music sign-in is DISABLED — DeveloperTokenManager failed to #{phase} token.
    Fix APPLE_MUSIC_PRIVATE_KEY (PKCS#8 PEM), APPLE_MUSIC_KEY_ID, and APPLE_MUSIC_TEAM_ID, then restart.

    #{Exception.format(:error, exception, stacktrace)}\
    """)
  end

  defp emit_attempt(phase, outcome)
       when phase in [:generate, :refresh, :regenerate, :retry] and outcome in [:ok, :error] do
    healthy = if outcome == :ok, do: 1, else: 0
    :telemetry.execute(@telemetry_event, %{count: 1, healthy: healthy}, %{phase: phase, outcome: outcome})
  end

  defp schedule_refresh(expires_at, existing_timer) do
    if existing_timer, do: Process.cancel_timer(existing_timer)
    ms = max((expires_at - System.system_time(:second) - @refresh_threshold) * 1_000, 0)
    Process.send_after(self(), :refresh_token, ms)
  end

  defp schedule_retry(%State{} = state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    timer_ref = Process.send_after(self(), :retry_generate, state.current_retry_ms)
    next_ms = min(state.current_retry_ms * state.retry_multiplier, state.retry_max_ms)
    {timer_ref, next_ms}
  end

  defp retry_opt(opts, opt_key, app_env_key, default) do
    Keyword.get(opts, opt_key, Application.get_env(:setlistify, app_env_key, default))
  end
end
