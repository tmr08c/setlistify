defmodule SetlistifyWeb.OAuthCallbackControllerTest do
  use SetlistifyWeb.ConnCase, async: false
  import Hammox
  alias Setlistify.Spotify.TokenManager

  setup do
    start_supervised!({Registry, keys: :unique, name: Setlistify.UserTokenRegistry})
    start_supervised!({DynamicSupervisor, name: Setlistify.UserTokenSupervisor})
    :ok
  end

  describe "OAuth callback handling" do
    test "successful callback starts token process and stores refresh token", %{conn: conn} do
      # Set up initial state
      oauth_state = "test_state"
      conn = conn |> init_test_session(%{}) |> put_session(:oauth_state, oauth_state)

      # Mock Spotify API calls
      expect(Req, :post!, fn "https://accounts.spotify.com/api/token", _opts ->
        %{
          status: 200,
          body: %{
            "access_token" => "test_access_token",
            "refresh_token" => "test_refresh_token",
            "expires_in" => 3600
          }
        }
      end)

      expect(Setlistify.Spotify.API.MockClient, :username, fn _client ->
        "test_user"
      end)

      # Simulate OAuth callback
      conn = get(conn, ~p"/oauth/callbacks/spotify?code=test_code&state=#{oauth_state}")

      # Verify token process was started
      assert {:ok, "test_access_token"} = TokenManager.get_token("test_user")

      # Verify refresh token was stored in session
      refresh_token = get_session(conn, :refresh_token)
      assert refresh_token
      assert {:ok, "test_refresh_token"} = Phoenix.Token.verify(SetlistifyWeb.Endpoint, "user auth", refresh_token, max_age: 86400 * 30)
    end

    test "sign out stops token process", %{conn: conn} do
      # Set up authenticated session
      username = "test_user"
      conn = conn
        |> init_test_session(%{})
        |> put_session("user", %{"username" => username})

      # Start a token process
      {:ok, _pid} = TokenManager.start_link({
        username,
        %{access_token: "test", refresh_token: "test", expires_in: 3600}
      })

      # Sign out
      get(conn, ~p"/signout")

      # Verify token process was stopped
      assert {:error, :not_found} = TokenManager.get_token(username)
    end

    test "invalid state parameter returns error", %{conn: conn} do
      conn = conn
        |> init_test_session(%{})
        |> put_session(:oauth_state, "correct_state")
        |> get(~p"/oauth/callbacks/spotify?code=test_code&state=wrong_state")

      assert get_flash(conn, :error) =~ "Response from Spotify did not match"
      assert redirected_to(conn) == "/"
    end
  end
end