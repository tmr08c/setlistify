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

  alias SetlistifyWeb.UserAuth
  alias Setlistify.Spotify.SessionSupervisor
  alias Setlistify.Spotify.API

  use SetlistifyWeb, :controller
  require OpenTelemetry.Tracer

  def new(conn, %{"provider" => "spotify", "code" => code, "state" => state}) do
    OpenTelemetry.Tracer.with_span "oauth_callback", %{
      attributes: [
        {"oauth.provider", "spotify"},
        {"oauth.has_code", true},
        {"oauth.state_valid", state == get_session(conn, :oauth_state)}
      ]
    } do
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

            # Add user ID to span
            OpenTelemetry.Tracer.set_attributes([{"user_id", user_session.user_id}])

            conn
            |> put_session(:refresh_token, encrypted_refresh_token)
            |> put_session(:user_id, user_session.user_id)
            |> UserAuth.auth_user(user_session.user_id)

          {:error, reason} ->
            # Record error in the span
            OpenTelemetry.Tracer.set_attributes([
              {"error", true},
              {"error.message", inspect(reason)}
            ])

            conn
            |> put_flash(:error, "Failed to authenticate with Spotify. Please try again.")
            |> redirect(to: ~p"/")
        end
      else
        # Record state mismatch error in the span
        OpenTelemetry.Tracer.set_attributes([
          {"error", true},
          {"error.type", "state_mismatch"}
        ])

        conn
        |> put_flash(:error, "Response from Spotify did not match. Please try again.")
        |> redirect(to: ~p"/")
      end
    end
  end

  @state_length 10
  def sign_in(conn, %{"provider" => "spotify"} = params) do
    OpenTelemetry.Tracer.with_span "oauth_sign_in", %{attributes: [{"oauth.provider", "spotify"}]} do
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

      # Add state to span for correlation with callback
      OpenTelemetry.Tracer.set_attributes([{"oauth.state", state}])

      conn
      |> put_session(:oauth_state, state)
      |> maybe_put_redirect_to(params)
      |> redirect(external: uri)
    end
  end

  defp maybe_put_redirect_to(conn, %{"redirect_to" => to}) when to != "" do
    put_session(conn, :redirect_to, to)
  end

  defp maybe_put_redirect_to(conn, _) do
    conn
  end

  def sign_out(conn, _) do
    user_id = get_session(conn, :user_id)

    OpenTelemetry.Tracer.with_span "oauth_sign_out", %{
      attributes: [
        {"has_user_id", user_id != nil}
      ]
    } do
      if user_id do
        OpenTelemetry.Tracer.set_attributes([{"user_id", user_id}])
      end

      # Log out user (which now handles clearing refresh token and the entire session)
      conn = UserAuth.log_out_user(conn)

      # Stop the session process
      if user_id do
        SessionSupervisor.stop_user_token(user_id)
      end

      # Return the updated conn
      conn
    end
  end
end
