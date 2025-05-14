defmodule Setlistify.Spotify.TokenManager do
  use GenServer
  require Logger
  alias Setlistify.Spotify.API

  # TODO: this name may not be the most clear for the goal. Does `  @refresh_buffer` make it more clear?
  # Refresh token 5 minutes before expiration
  @refresh_threshold 5 * 60

  # Client API

  def start_link({user_id, initial_tokens}) do
    name = via_tuple(user_id)
    GenServer.start_link(__MODULE__, initial_tokens, name: name)
  end

  def get_token(user_id) do
    case lookup(user_id) do
      {:ok, pid} ->
        GenServer.call(pid, :get_token)

      :error ->
        {:error, :not_found}
    end
  end

  def refresh_token(user_id) do
    case lookup(user_id) do
      {:ok, pid} -> GenServer.call(pid, :refresh_token)
      :error -> {:error, :not_found}
    end
  end

  def stop(user_id) do
    case lookup(user_id) do
      {:ok, pid} ->
        GenServer.stop(pid, :normal)

      :error ->
        {:error, :not_found}
    end
  end

  # Server Callbacks

  @impl true
  def init(
        %{access_token: _access_token, refresh_token: _refresh_token, expires_in: expires_in} =
          tokens
      ) do
    # Schedule token refresh
    # TODO: This can be put into a `handle_continue` call. It's not necessary, but feels like a good fit
    schedule_refresh(expires_in - @refresh_threshold)
    {:ok, Map.put(tokens, :expires_at, timestamp() + expires_in)}
  end

  @impl true
  def handle_call(:get_token, _from, %{access_token: token} = state) do
    {:reply, {:ok, token}, state}
  end

  @impl true
  def handle_call(:refresh_token, _from, %{refresh_token: refresh_token} = state) do
    case API.refresh_token(refresh_token) do
      {:ok, new_tokens} ->
        schedule_refresh(new_tokens.expires_in - @refresh_threshold)

        new_state =
          Map.merge(state, new_tokens)
          |> Map.put(:expires_at, timestamp() + new_tokens.expires_in)

        {:reply, {:ok, new_tokens.access_token}, new_state}

      {:error, reason} = error ->
        Logger.error("Failed to refresh token: #{inspect(reason)}")
        {:stop, :normal, error, state}
    end
  end

  @impl true
  def handle_info(:refresh_token, %{refresh_token: refresh_token} = state) do
    case API.refresh_token(refresh_token) do
      {:ok, new_tokens} ->
        schedule_refresh(new_tokens.expires_in - @refresh_threshold)

        new_state =
          Map.merge(state, new_tokens)
          |> Map.put(:expires_at, timestamp() + new_tokens.expires_in)

        {:noreply, new_state}

      {:error, _reason} ->
        {:stop, :normal, state}
    end
  end

  # Helper functions

  defp via_tuple(user_id) do
    {:via, Registry, {Setlistify.UserTokenRegistry, user_id}}
  end

  @doc """
  Looks up a token manager process by user ID.
  Returns {:ok, pid} if found, :error otherwise.
  """
  def lookup(user_id) do
    case Registry.lookup(Setlistify.UserTokenRegistry, user_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  defp schedule_refresh(after_seconds) when after_seconds > 0 do
    Process.send_after(self(), :refresh_token, :timer.seconds(after_seconds))
  end

  defp schedule_refresh(_), do: Process.send(self(), :refresh_token, [])

  defp timestamp, do: System.system_time(:second)
end
