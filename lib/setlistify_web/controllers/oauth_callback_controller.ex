defmodule SetlistifyWeb.OAuthCallbackController do
  alias SetlistifyWeb.UserAuth
  alias Setlistify.Spotify
  alias Setlistify.Spotify.TokenSupervisor

  use SetlistifyWeb, :controller

  def new(conn, %{"provider" => "spotify", "code" => code, "state" => state}) do
    if state == get_session(conn, :oauth_state) do
      auth =
        :base64.encode(
          Application.fetch_env!(:setlistify, :spotify_client_id) <>
            ":" <> Application.fetch_env!(:setlistify, :spotify_client_secret)
        )

      resp =
        Req.post!(
          "https://accounts.spotify.com/api/token",
          headers: %{authorization: "Basic #{auth}"},
          form: %{
            grant_type: :authorization_code,
            code: code,
            redirect_uri: url(~p"/oauth/callbacks/spotify")
          }
        )

      %{
        "access_token" => access_token,
        "refresh_token" => refresh_token,
        "expires_in" => expires_in
      } = resp.body

      username = access_token |> Spotify.API.new() |> Spotify.API.username()

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

      # TODO should we be putting the "user" key on the sesion
      conn
      |> put_session(:refresh_token, encrypted_refresh_token)
      |> UserAuth.auth_user({username, access_token})
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
    # TODO: Are we putting the "user" key on the session somewhere?
    # TODO: Would it make sense for a helper function to be on UserAuth, so we could have `auth_user` and `sign_out_user` logic close together?
    case get_session(conn, "user") do
      %{"username" => username} -> TokenSupervisor.stop_user_token(username)
      _ -> :ok
    end

    UserAuth.log_out_user(conn)
  end
end
