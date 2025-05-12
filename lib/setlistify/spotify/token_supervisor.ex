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
    TokenManager.stop(user_id)
  end

  def get_token(user_id) do
    TokenManager.get_token(user_id)
  end

  def refresh_token(user_id) do
    TokenManager.refresh_token(user_id)
  end
end