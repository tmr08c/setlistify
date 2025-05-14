defmodule SetlistifyWeb.OAuthCallbackController do
  alias SetlistifyWeb.UserAuth
  alias Setlistify.Spotify.TokenSupervisor
  alias Setlistify.Spotify.API

  use SetlistifyWeb, :controller

  def new(conn, %{"provider" => "spotify", "code" => code, "state" => state}) do
    if state == get_session(conn, :oauth_state) do
      # Exchange authorization code for access and refresh tokens
      redirect_uri = url(~p"/oauth/callbacks/spotify")

      case API.exchange_code(code, redirect_uri) do
        {:ok, %{access_token: access_token, refresh_token: refresh_token, expires_in: expires_in}} ->
          username = access_token |> API.new() |> API.username()

          # Create encrypted token for session storage
          encrypted_refresh_token =
            Phoenix.Token.sign(SetlistifyWeb.Endpoint, "user auth", refresh_token)

          # Start token manager process
          TokenSupervisor.start_user_token(
            username,
            %{
              access_token: access_token,
              refresh_token: refresh_token,
              expires_in: expires_in
            }
          )

          # TODO should we be putting the "user" key on the session
          conn
          |> put_session(:refresh_token, encrypted_refresh_token)
          |> UserAuth.auth_user({username, access_token})

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

    # Extract username before clearing session
    username =
      case user_session do
        %{"username" => username} -> username
        _ -> nil
      end

    # Log out user (which now handles clearing refresh token and the entire session)
    conn = UserAuth.log_out_user(conn)

    # Now stop the token process AFTER clearing the session
    # This ensures that if any autorestart mechanism exists, it won't have the refresh token anymore
    if username, do: TokenSupervisor.stop_user_token(username)

    # Return the updated conn
    conn
  end
end
