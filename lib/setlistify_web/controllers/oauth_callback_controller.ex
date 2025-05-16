defmodule SetlistifyWeb.OAuthCallbackController do
  alias SetlistifyWeb.UserAuth
  alias Setlistify.Spotify.SessionSupervisor
  alias Setlistify.Spotify.API

  use SetlistifyWeb, :controller

  def new(conn, %{"provider" => "spotify", "code" => code, "state" => state}) do
    if state == get_session(conn, :oauth_state) do
      # Exchange authorization code for access and refresh tokens
      redirect_uri = url(~p"/oauth/callbacks/spotify")

      case API.exchange_code(code, redirect_uri) do
        {:ok, user_session} ->
          # Create encrypted token for session storage
          encrypted_refresh_token =
            Phoenix.Token.sign(SetlistifyWeb.Endpoint, "user auth", user_session.refresh_token)

          # Start session manager process with UserSession
          # TODO Consider if this should be called in `exchange_code`
          SessionSupervisor.start_user_token(user_session.user_id, user_session)

          conn
          |> put_session(:refresh_token, encrypted_refresh_token)
          |> put_session(:user_id, user_session.user_id)
          |> UserAuth.auth_user(user_session.user_id)

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Failed to authenticate with Spotify. Please try again.")
          |> redirect(to: ~p"/")
      end
    else
      conn
      |> put_flash(:error, "Response from Spotify did not match. Please try again.")
      |> redirect(to: ~p"/")
    end
  end

  @state_length 10
  def sign_in(conn, %{"provider" => "spotify"} = params) do
    state =
      :crypto.strong_rand_bytes(@state_length)
      |> Base.url_encode64()
      |> binary_part(0, @state_length)

    uri =
      "https://accounts.spotify.com/authorize"
      |> URI.new!()
      |> URI.append_query(
        URI.encode_query(%{
          client_id: Application.fetch_env!(:setlistify, :spotify_client_id),
          response_type: "code",
          redirect_uri: url(~p"/oauth/callbacks/spotify"),
          state: state,
          scope: "playlist-modify-private",
          show_dialog: true
        })
      )
      |> URI.to_string()

    conn
    |> put_session(:oauth_state, state)
    |> maybe_put_redirect_to(params)
    |> redirect(external: uri)
  end

  defp maybe_put_redirect_to(conn, %{"redirect_to" => to}) when to != "" do
    put_session(conn, :redirect_to, to)
  end

  defp maybe_put_redirect_to(conn, _) do
    conn
  end

  def sign_out(conn, _) do
    user_session = get_session(conn, "user")
    user_id = get_session(conn, :user_id)

    # Extract username for legacy compatibility
    username =
      case user_session do
        %{"username" => username} -> username
        _ -> nil
      end

    # Log out user (which now handles clearing refresh token and the entire session)
    conn = UserAuth.log_out_user(conn)

    # Stop the session process using user_id or fallback to username
    cond do
      user_id -> SessionSupervisor.stop_user_token(user_id)
      username -> SessionSupervisor.stop_user_token(username)
      true -> nil
    end

    # Return the updated conn
    conn
  end
end
