defmodule SetlistifyWeb.OAuthFlowTest do
  use SetlistifyWeb.ConnCase, async: false
  import Hammox

  alias Setlistify.Spotify.SessionManager

  setup do
    # Generate a unique user ID for each test to prevent test pollution
    test_user = unique_user_id()

    # Set environment variables for tests
    :ok = Application.put_env(:setlistify, :spotify_client_id, "test_client_id")
    :ok = Application.put_env(:setlistify, :spotify_client_secret, "test_client_secret")

    # Set up Mox expectations
    Hammox.stub(Setlistify.Spotify.API.MockClient, :new, fn token ->
      Req.new(base_url: "https://api.spotify.com/v1/", auth: {:bearer, token})
    end)

    {:ok, %{test_user: test_user}}
  end

  describe "Full OAuth authentication flow" do
    test "sign in, callback, and sign out flow works correctly", %{
      conn: conn,
      test_user: test_user
    } do
      # Step 1: Test the initial sign-in link with redirect_to parameter
      redirect_to = "/setlist/12345"
      signin_conn = get(conn, ~p"/signin/spotify?redirect_to=#{redirect_to}")

      # Should set the OAuth state and redirect_to in session
      assert get_session(signin_conn, :oauth_state) != nil
      assert get_session(signin_conn, :redirect_to) == redirect_to

      # Should redirect to Spotify authorization URL
      assert signin_conn.status == 302
      assert redirected_to(signin_conn) =~ "https://accounts.spotify.com/authorize"

      # Step 2: Test the callback with successful token exchange
      oauth_state = get_session(signin_conn, :oauth_state)

      callback_conn =
        conn
        |> init_test_session(%{})
        |> put_session(:oauth_state, oauth_state)
        |> put_session(:redirect_to, redirect_to)
        |> fetch_flash()

      # Set up mock for the token exchange
      expect(Setlistify.Spotify.API.MockClient, :exchange_code, fn code, redirect_uri ->
        assert code == "test_code"
        assert redirect_uri =~ "/oauth/callbacks/spotify"

        {:ok,
         %Setlistify.Spotify.UserSession{
           access_token: "test_access_token",
           refresh_token: "test_refresh_token",
           expires_at: System.system_time(:second) + 3600,
           user_id: test_user,
           username: test_user
         }}
      end)

      # Process the callback
      callback_response =
        get(callback_conn, ~p"/oauth/callbacks/spotify?code=test_code&state=#{oauth_state}")

      # Should have created a session process
      assert {:ok, "test_access_token"} = SessionManager.get_token(test_user)

      # Should redirect to the original page
      assert callback_response.status == 302
      assert redirected_to(callback_response) =~ redirect_to

      # Step 3: Test sign out
      signout_conn =
        callback_conn
        |> put_session(:refresh_token, "test_refresh_token")
        |> put_session(:user_id, test_user)

      # Process signout
      signout_response = get(signout_conn, ~p"/signout")

      # Session process should be stopped
      refute_in_registry(test_user)

      # Session should be cleared
      refute get_session(signout_response, :refresh_token)

      # Should redirect to home page
      assert signout_response.status == 302
      assert redirected_to(signout_response) == "/"
    end

    @tag :capture_log
    test "sign in with invalid state shows error", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:oauth_state, "correct_state")
        |> fetch_flash()

      # Use wrong state parameter
      response = get(conn, ~p"/oauth/callbacks/spotify?code=test_code&state=wrong_state")

      # Should show error message
      assert Phoenix.Flash.get(response.assigns.flash, :error) =~
               "Response from Spotify did not match"

      # Should redirect to home page
      assert redirected_to(response) == "/"
    end

    @tag :capture_log
    test "sign in with failed token exchange shows error", %{conn: conn} do
      # Set up the session state
      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:oauth_state, "test_state")
        |> fetch_flash()

      # Mock the token exchange to fail
      expect(Setlistify.Spotify.API.MockClient, :exchange_code, fn _code, _redirect_uri ->
        {:error, :invalid_code}
      end)

      # Process the callback
      response = get(conn, ~p"/oauth/callbacks/spotify?code=test_code&state=test_state")

      # Should show error message
      assert Phoenix.Flash.get(response.assigns.flash, :error) =~
               "Failed to authenticate with Spotify"

      # Should redirect to home page
      assert redirected_to(response) == "/"
    end
  end
end
