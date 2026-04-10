defmodule SetlistifyWeb.OAuthCallbackController do
  @moduledoc """
  Handles OAuth2 authentication flow with Spotify.

  This controller manages the complete OAuth2 authorization code flow:
  1. Redirects users to Spotify for authorization
  2. Handles the callback from Spotify with authorization code
  3. Exchanges the code for access/refresh tokens
  4. Creates user sessions and manages authentication state

  ## OAuth Flow Diagram

  ```mermaid
  sequenceDiagram
    participant User
    participant Browser
    participant App as Setlistify App
    participant OAuth as OAuthCallbackController
    participant API as Spotify API
    participant Auth as UserAuth
    participant SM as SessionManager
    participant SS as SessionSupervisor

    User->>Browser: Click "Sign in with Spotify"
    Browser->>App: GET /signin/spotify
    App->>OAuth: sign_in(conn, %{"provider" => "spotify"})
    OAuth->>OAuth: Generate random state
    OAuth->>Browser: Redirect to Spotify OAuth
    Browser->>API: Authorization request
    API->>Browser: Show consent screen
    User->>Browser: Approve access
    Browser->>API: User consent
    API->>Browser: Redirect with code & state
    Browser->>App: GET /oauth/callbacks/spotify?code=XXX&state=YYY
    App->>OAuth: new(conn, %{"code" => code, "state" => state})
    OAuth->>OAuth: Verify state matches
    OAuth->>API: Exchange code for tokens
    API->>OAuth: Return tokens & user data
    OAuth->>OAuth: Create UserSession struct
    OAuth->>SS: Start session manager process
    SS->>SM: Create new SessionManager
    OAuth->>Auth: auth_user(conn, user_id)
    Auth->>Browser: Set session cookies
    Auth->>Browser: Redirect to original path or root
    Browser->>User: Authenticated app page
  ```

  ## Security Considerations

  - State parameter prevents CSRF attacks by ensuring the callback matches the original request
  - Tokens are encrypted before storing in session cookies
  - Refresh tokens are never exposed to the client
  - SessionManager handles automatic token refresh
  """

  use SetlistifyWeb, :controller

  alias Setlistify.AppleMusic
  alias Setlistify.Auth.TokenSalts
  alias Setlistify.Spotify
  alias SetlistifyWeb.UserAuth

  def new(conn, %{"provider" => "spotify", "code" => code, "state" => state}) do
    if state == get_session(conn, :oauth_state) do
      # Exchange authorization code for access and refresh tokens
      redirect_uri = url(~p"/oauth/callbacks/spotify")

      case Spotify.API.exchange_code(code, redirect_uri) do
        {:ok, user_session} ->
          # Create encrypted token for session storage
          encrypted_refresh_token =
            Phoenix.Token.sign(
              SetlistifyWeb.Endpoint,
              TokenSalts.spotify_refresh_token(),
              user_session.refresh_token
            )

          Spotify.SessionSupervisor.start_user_token(user_session.user_id, user_session)

          conn
          |> put_session(:auth_provider, "spotify")
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

  def new_apple_music(conn, %{"user_token" => user_token, "storefront" => storefront} = params) do
    user_id = Ecto.UUID.generate()
    {:ok, user_session} = AppleMusic.API.build_user_session(user_token, storefront, user_id)
    {:ok, _pid} = AppleMusic.SessionSupervisor.start_user_token(user_id, user_session)

    encrypted_user_token =
      Phoenix.Token.sign(SetlistifyWeb.Endpoint, TokenSalts.apple_music_user_token(), user_token)

    conn
    |> put_session(:auth_provider, "apple_music")
    |> put_session(:user_token, encrypted_user_token)
    |> put_session(:storefront, storefront)
    |> maybe_put_redirect_to(params)
    |> UserAuth.auth_user(user_id)
  end

  @state_length 10
  def sign_in(conn, %{"provider" => "spotify"} = params) do
    state =
      @state_length
      |> :crypto.strong_rand_bytes()
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
    user_id = get_session(conn, :user_id)
    auth_provider = get_session(conn, :auth_provider)

    conn = UserAuth.log_out_user(conn)

    case {auth_provider, user_id} do
      {"spotify", id} when not is_nil(id) -> Spotify.SessionSupervisor.stop_user_token(id)
      {"apple_music", id} when not is_nil(id) -> AppleMusic.SessionSupervisor.stop_user_token(id)
      _ -> :ok
    end

    conn
  end
end
