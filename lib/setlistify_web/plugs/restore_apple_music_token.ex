defmodule SetlistifyWeb.Plugs.RestoreAppleMusicToken do
  @moduledoc """
  A plug that restores Apple Music session processes from encrypted session tokens.

  This plug checks if an Apple Music session process exists for the user_id stored
  in the session. If not, it reconstructs the `UserSession` from cookie values
  (user_id, encrypted user_token, storefront) — no network call required.
  """
  import Plug.Conn
  require Logger

  alias Setlistify.AppleMusic.{SessionManager, SessionSupervisor, API}
  alias Setlistify.Auth.TokenSalts

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :auth_provider) == "apple_music" do
      restore_session(conn)
    else
      conn
    end
  end

  defp restore_session(conn) do
    user_id = get_session(conn, :user_id)
    encrypted_token = get_session(conn, :user_token)
    storefront = get_session(conn, :storefront)

    case SessionManager.get_session(user_id) do
      {:ok, _session} ->
        conn

      {:error, :not_found} ->
        with user_id when not is_nil(user_id) <- user_id,
             {:ok, user_token} <- decrypt_token(encrypted_token),
             storefront when not is_nil(storefront) <- storefront,
             {:ok, user_session} <- API.build_user_session(user_token, storefront, user_id) do
          SessionSupervisor.start_user_token(user_id, user_session)
          conn
        else
          _ ->
            conn
            |> clear_session()
            |> Phoenix.Controller.put_flash(:error, "Session expired. Please sign in again.")
        end
    end
  end

  defp decrypt_token(nil), do: {:error, :missing}

  defp decrypt_token(encrypted) do
    Phoenix.Token.verify(SetlistifyWeb.Endpoint, TokenSalts.apple_music_user_token(), encrypted,
      max_age: 86_400 * 180
    )
  end
end
