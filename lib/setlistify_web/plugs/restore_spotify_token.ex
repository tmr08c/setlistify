defmodule SetlistifyWeb.Plugs.RestoreSpotifyToken do
  @moduledoc """
  A plug that restores Spotify token processes from encrypted session tokens.

  This plug checks if a session process exists for the user_id stored in the session.
  If not, it attempts to use the stored refresh token to create a new session process.
  """
  import Plug.Conn

  alias Setlistify.Spotify.{SessionSupervisor, SessionManager, API}
  alias Setlistify.Auth.TokenSalts

  def init(opts), do: opts

  def call(conn, _opts) do
    auth_provider = get_session(conn, :auth_provider)

    if auth_provider != "spotify" do
      conn
    else
      do_call(conn)
    end
  end

  defp do_call(conn) do
    user_id = get_session(conn, :user_id)
    refresh_token = get_session(conn, :refresh_token)

    with "spotify" <- get_session(conn, :auth_provider),
         user_id when not is_nil(user_id) <- user_id,
         {:error, :not_found} <- SessionManager.get_session(user_id),
         encrypted_token when not is_nil(encrypted_token) <- refresh_token,
         {:ok, refresh_token} <-
           Phoenix.Token.verify(
             SetlistifyWeb.Endpoint,
             TokenSalts.spotify_refresh_token(),
             encrypted_token,
             max_age: 86400 * 30
           ) do
      case API.refresh_to_user_session(refresh_token) do
        {:ok, user_session} ->
          {:ok, _pid} = SessionSupervisor.start_user_token(user_id, user_session)
          conn

        {:error, _reason} ->
          # If refresh fails, clear the session but continue with the request
          conn
          |> clear_session()
          |> Phoenix.Controller.put_flash(
            :error,
            "Your Spotify session has expired. Please log in again."
          )
      end
    else
      _ -> conn
    end
  end
end
