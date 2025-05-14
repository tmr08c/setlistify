defmodule Setlistify.Spotify.TokenSupervisor do
  @moduledoc """
  Supervisor for managing Spotify user token processes.
  """

  alias Setlistify.Spotify.TokenManager

  def start_user_token(user_id, tokens) do
    DynamicSupervisor.start_child(
      Setlistify.UserTokenSupervisor,
      {TokenManager, {user_id, tokens}}
    )
  end

  def stop_user_token(user_id) do
    # Find the pid using the registry and terminate the child
    case TokenManager.lookup(user_id) do
      {:ok, pid} ->
        # Use DynamicSupervisor.terminate_child to remove it from supervision
        # This will return :ok on success or {:error, :not_found} if the process isn't found
        :ok = DynamicSupervisor.terminate_child(Setlistify.UserTokenSupervisor, pid)

      :error ->
        # No process found in the registry, just return the same error as DynamicSupervisor would
        {:error, :not_found}
    end
  end

  def get_token(user_id) do
    TokenManager.get_token(user_id)
  end

  def refresh_token(user_id) do
    TokenManager.refresh_token(user_id)
  end
end
