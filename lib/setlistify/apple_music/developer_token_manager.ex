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
  a periodic retry. Callers receive `nil` from `get_token/0` (the layout's existing
  guard hides the sign-in UI). The retry keeps the failure surfacing in logs so a
  silent launch with bad config is hard to miss, and self-heals if the config is
  fixed via `Application.put_env` in a running node. Once the operator restarts
  with corrected config, normal operation resumes.

  Every error log carries `apple_music_token_phase` metadata
  (`:generate | :refresh | :regenerate | :retry`) so structured-log queries can
  distinguish which lifecycle hook failed.

  If the cached token's `expires_at` passes while the manager is stuck retrying
  (e.g. signing has been broken for the token's whole 30-day lifetime),
  `get_token/0` returns `nil` rather than handing back an expired binary.
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
            retry_interval_ms: pos_integer()
          }

    @enforce_keys [:retry_interval_ms]
    defstruct [:token, :expires_at, :timer_ref, :retry_interval_ms]
  end

  @refresh_threshold 5 * 60
  @default_ttl_seconds 30 * 24 * 60 * 60
  @default_retry_interval_ms 5 * 60 * 1_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Returns the cached developer token, or `nil` if generation has failed or the token has expired."
  def get_token, do: GenServer.call(__MODULE__, :get_token)

  @doc """
  Forces immediate token regeneration and returns the new token.
  Called on a 401 response from ExternalClient. Cancels the pending scheduled
  refresh and reschedules from the new expiry to prevent a double refresh.

  Returns the existing cached token (which may be `nil` in degraded mode) if
  regeneration fails.
  """
  def regenerate_token, do: GenServer.call(__MODULE__, :regenerate_token)

  def init(opts) do
    retry_interval_ms = Keyword.get(opts, :retry_interval_ms, @default_retry_interval_ms)
    {:ok, %State{retry_interval_ms: retry_interval_ms}, {:continue, :generate_token}}
  end

  def handle_continue(:generate_token, %State{} = state) do
    case generate_and_sign() do
      {:ok, token, expires_at} ->
        timer_ref = schedule_refresh(expires_at, state.timer_ref)
        {:noreply, %{state | token: token, expires_at: expires_at, timer_ref: timer_ref}}

      {:error, reason} ->
        log_token_error(:generate, reason)
        timer_ref = schedule_retry(state)
        {:noreply, %{state | token: nil, expires_at: nil, timer_ref: timer_ref}}
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
    case generate_and_sign() do
      {:ok, token, expires_at} ->
        timer_ref = schedule_refresh(expires_at, state.timer_ref)
        new_state = %{state | token: token, expires_at: expires_at, timer_ref: timer_ref}
        {:reply, token, new_state}

      {:error, reason} ->
        log_token_error(:regenerate, reason)
        {:reply, state.token, state}
    end
  end

  def handle_info(:refresh_token, %State{} = state) do
    case generate_and_sign() do
      {:ok, token, expires_at} ->
        timer_ref = schedule_refresh(expires_at, state.timer_ref)
        {:noreply, %{state | token: token, expires_at: expires_at, timer_ref: timer_ref}}

      {:error, reason} ->
        log_token_error(:refresh, reason)
        timer_ref = schedule_retry(state)
        {:noreply, %{state | timer_ref: timer_ref}}
    end
  end

  def handle_info(:retry_generate, %State{} = state) do
    case generate_and_sign() do
      {:ok, token, expires_at} ->
        Logger.info("Apple Music developer token recovered after earlier failure",
          apple_music_token_phase: :recovered
        )

        timer_ref = schedule_refresh(expires_at, state.timer_ref)
        {:noreply, %{state | token: token, expires_at: expires_at, timer_ref: timer_ref}}

      {:error, reason} ->
        log_token_error(:retry, reason)
        timer_ref = schedule_retry(state)
        {:noreply, %{state | timer_ref: timer_ref}}
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
    Logger.error(
      """
      Apple Music sign-in is DISABLED — DeveloperTokenManager failed to #{phase} token.
      Fix APPLE_MUSIC_PRIVATE_KEY (PKCS#8 PEM), APPLE_MUSIC_KEY_ID, and APPLE_MUSIC_TEAM_ID, then restart.

      #{Exception.format(:error, exception, stacktrace)}\
      """,
      apple_music_token_phase: phase
    )
  end

  defp schedule_refresh(expires_at, existing_timer) do
    if existing_timer, do: Process.cancel_timer(existing_timer)
    ms = max((expires_at - System.system_time(:second) - @refresh_threshold) * 1_000, 0)
    Process.send_after(self(), :refresh_token, ms)
  end

  defp schedule_retry(%State{timer_ref: existing_timer, retry_interval_ms: ms}) do
    if existing_timer, do: Process.cancel_timer(existing_timer)
    Process.send_after(self(), :retry_generate, ms)
  end
end
