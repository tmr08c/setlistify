defmodule Setlistify.AppleMusic.DeveloperTokenManager do
  use GenServer

  require Logger

  require Logger

  @refresh_threshold 5 * 60
  @default_ttl_seconds 30 * 24 * 60 * 60

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

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
