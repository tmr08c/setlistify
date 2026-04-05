defmodule Setlistify.AppleMusic.API do
  @moduledoc """
  Interface module for Apple Music API operations.
  """

  alias Setlistify.AppleMusic.UserSession

  @spec build_user_session(String.t(), String.t(), String.t()) :: {:ok, UserSession.t()}
  def build_user_session(user_token, storefront, user_id) do
    {:ok, %UserSession{user_token: user_token, storefront: storefront, user_id: user_id}}
  end
end
