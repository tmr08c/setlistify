defmodule SetlistifyWeb.OAuthCallbackSessionTest do
  use SetlistifyWeb.ConnCase
  import Hammox

  alias Setlistify.Spotify.UserSession
  import Setlistify.Test.RegistryHelpers

  describe "OAuth callback session handling" do
    test "properly sets user_id in session after successful OAuth flow", %{conn: conn} do
      # Setup test data
      mock_code = "test_authorization_code"
      mock_state = "test_state"
      redirect_uri = "http://localhost:4002/oauth/callbacks/spotify"
      user_id = unique_user_id()

      # Create expected UserSession
      user_session = %UserSession{
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        expires_at: System.system_time(:second) + 3600,
        user_id: user_id,
        username: "test_username"
      }

      # Mock the API exchange_code call
      expect(Setlistify.Spotify.API.MockClient, :exchange_code, fn ^mock_code, ^redirect_uri ->
        {:ok, user_session}
      end)

      # Setup conn with OAuth state
      conn =
        conn
        |> init_test_session(%{"oauth_state" => mock_state})
        |> fetch_flash()

      # Make the OAuth callback request
      conn =
        get(conn, ~p"/oauth/callbacks/spotify", %{
          "provider" => "spotify",
          "code" => mock_code,
          "state" => mock_state
        })

      # Verify the session was set correctly
      assert get_session(conn, "user_id") == user_id
      assert get_session(conn, "refresh_token") != nil

      # Verify old session structure is NOT present
      refute get_session(conn, "access_token")
      refute get_session(conn, "account_name")

      # Verify SessionManager was started with the user session
      assert_in_registry(user_id)

      # Verify redirect happened
      assert conn.status == 302
      location = Plug.Conn.get_resp_header(conn, "location") |> List.first()
      assert location == "http://localhost:4002/" || location == "/"
    end

    test "OAuth flow does not set old session keys", %{conn: conn} do
      # This test verifies the OAuth flow doesn't use the old session structure
      mock_code = "test_authorization_code"
      mock_state = "test_state"
      redirect_uri = "http://localhost:4002/oauth/callbacks/spotify"
      user_id = unique_user_id()

      user_session = %UserSession{
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        expires_at: System.system_time(:second) + 3600,
        user_id: user_id,
        username: "test_username"
      }

      expect(Setlistify.Spotify.API.MockClient, :exchange_code, fn ^mock_code, ^redirect_uri ->
        {:ok, user_session}
      end)

      conn =
        conn
        |> init_test_session(%{"oauth_state" => mock_state})
        |> fetch_flash()

      conn =
        get(conn, ~p"/oauth/callbacks/spotify", %{
          "provider" => "spotify",
          "code" => mock_code,
          "state" => mock_state
        })

      # The buggy code would set these old keys
      assert get_session(conn, "access_token") == nil, "access_token should not be in session"
      assert get_session(conn, "account_name") == nil, "account_name should not be in session"
    end

    test "session keys are preserved through auth_user renew_session flow", %{conn: conn} do
      # This test specifically verifies that auth_user doesn't clear the session data
      user_id = unique_user_id()

      encrypted_refresh_token =
        Phoenix.Token.sign(SetlistifyWeb.Endpoint, "user auth", "test_refresh")

      # Setup initial session
      conn =
        conn
        |> init_test_session(%{
          "user_id" => user_id,
          "refresh_token" => encrypted_refresh_token,
          "redirect_to" => "/some/path"
        })

      # Call auth_user directly
      conn = SetlistifyWeb.UserAuth.auth_user(conn, {"username", "token"})

      # Verify session data was preserved
      assert get_session(conn, "user_id") == user_id
      assert get_session(conn, "refresh_token") == encrypted_refresh_token

      # Verify old keys are not added
      refute get_session(conn, "access_token")
      refute get_session(conn, "account_name")

      # Verify redirect preserved
      assert redirected_to(conn) == "/some/path"
    end
  end
end
