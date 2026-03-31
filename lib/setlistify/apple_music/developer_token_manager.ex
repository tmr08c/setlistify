defmodule Setlistify.AppleMusic.DeveloperTokenManager do
  @moduledoc """
  Singleton GenServer that generates and caches the Apple Music developer token.

  Unlike user tokens, the developer token is not tied to any individual user — it
  identifies the app itself to Apple's API and is shared across all requests. Apple
  issues developer tokens as ES256-signed JWTs with a maximum lifetime of 180 days,
  though we sign ours for 30 days.

  Because the token must be present before any Apple Music API call can succeed, this
  process generates the token eagerly on startup (via `handle_continue`) rather than
  lazily on first call. Callers are guaranteed to receive a non-nil token even on the
  very first `get_token/0` call.

  ## Rotation

  The token is automatically rotated 5 minutes before it expires. A `Process.send_after`
  timer fires a `:refresh_token` message, which regenerates and caches a fresh token
  before the old one becomes invalid. This means callers never need to think about
  expiry — `get_token/0` always returns a valid token.

  If token generation fails (e.g. misconfigured PEM or missing env vars), the process
  logs the error and stops, allowing the supervisor to handle the restart policy.
  """

  use GenServer

  require Logger

  @refresh_threshold 5 * 60
  @default_ttl_seconds 30 * 24 * 60 * 60

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Returns the cached developer token. Always valid — rotation is handled automatically."
  def get_token, do: GenServer.call(__MODULE__, :get_token)

  def init(_),
    do: {:ok, %{token: nil, expires_at: nil, timer_ref: nil}, {:continue, :generate_token}}

  def handle_continue(:generate_token, state) do
    case generate_and_sign() do
      {:ok, token, expires_at} ->
        timer_ref = schedule_refresh(expires_at, state.timer_ref)
        {:noreply, %{state | token: token, expires_at: expires_at, timer_ref: timer_ref}}

      {:error, reason} ->
        Logger.error("DeveloperTokenManager failed to generate token: #{inspect(reason)}")
        {:stop, reason, state}
    end
  end

  def handle_call(:get_token, _from, state), do: {:reply, state.token, state}

  def handle_info(:refresh_token, state) do
    case generate_and_sign() do
      {:ok, token, expires_at} ->
        timer_ref = schedule_refresh(expires_at, state.timer_ref)
        {:noreply, %{state | token: token, expires_at: expires_at, timer_ref: timer_ref}}

      {:error, reason} ->
        Logger.error("DeveloperTokenManager failed to refresh token: #{inspect(reason)}")
        {:stop, reason, state}
    end
  end

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
    e -> {:error, e}
  end

  defp schedule_refresh(expires_at, existing_timer) do
    if existing_timer, do: Process.cancel_timer(existing_timer)
    ms = max((expires_at - System.system_time(:second) - @refresh_threshold) * 1_000, 0)
    Process.send_after(self(), :refresh_token, ms)
  end
end
