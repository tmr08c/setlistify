defmodule Setlistify.AppleMusic.API do
  @moduledoc """
  Interface module for Apple Music API operations.

  `build_user_session/3` is a pure struct constructor — it makes no network
  calls. Both the sign-in flow and session restoration use it to reconstruct a
  `UserSession` from its component parts.

  HTTP operations (`search_for_track/3`, `create_playlist/3`, etc.) will be
  added in Phase 4 (#68) via an `ExternalClient` implementation.
  """

  alias Setlistify.AppleMusic.UserSession

  @spec build_user_session(String.t(), String.t(), String.t()) :: {:ok, UserSession.t()}
  def build_user_session(user_token, storefront, user_id) do
    {:ok, %UserSession{user_token: user_token, storefront: storefront, user_id: user_id}}
  end
end
