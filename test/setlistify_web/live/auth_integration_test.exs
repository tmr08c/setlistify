defmodule SetlistifyWeb.Live.AuthIntegrationTest do
  use SetlistifyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Setlistify.Spotify.{SessionManager, UserSession}
  alias Setlistify.AppleMusic
  import Setlistify.Test.RegistryHelpers

  describe "LiveView authentication integration" do
    test "authenticated user session is properly loaded in LiveView", %{conn: conn} do
      # Setup user and session
      user_id = unique_user_id()

      user_session = %UserSession{
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        expires_at: System.system_time(:second) + 3600,
        user_id: user_id,
        username: "test_user"
      }

      # Start SessionManager
      {:ok, _pid} = SessionManager.start_link({user_id, user_session})

      # Setup conn with user_id in session
      conn =
        conn
        |> init_test_session(%{"user_id" => user_id, "auth_provider" => "spotify"})
        |> fetch_flash()

      # Load a LiveView page
      {:ok, _view, html} = live(conn, ~p"/")

      # Verify the user is shown as logged in
      assert html =~ "Signed in as test_user"
      assert html =~ "Sign Out"
      refute html =~ "Sign in"
    end

    test "unauthenticated user sees sign in prompt in LiveView", %{conn: conn} do
      # Setup conn without session
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()

      # Load a LiveView page
      {:ok, _view, html} = live(conn, ~p"/")

      # Verify the user is shown as logged out
      assert html =~ "Sign in"
      refute html =~ "Sign Out"
      refute html =~ "Signed in as"
    end

    test "LiveView handles missing SessionManager gracefully", %{conn: conn} do
      # Setup user_id in session but no SessionManager
      user_id = "nonexistent_user"

      conn =
        conn
        |> init_test_session(%{"user_id" => user_id})
        |> fetch_flash()

      # Load a LiveView page - should not crash
      {:ok, _view, html} = live(conn, ~p"/")

      # Should show as logged out since SessionManager lookup fails
      assert html =~ "Sign in"
      refute html =~ "Sign Out"
    end

    test "authenticated Apple Music user session is properly loaded in LiveView", %{conn: conn} do
      user_id = unique_user_id()

      user_session = %AppleMusic.UserSession{
        user_token: "test_user_token",
        storefront: "us",
        user_id: user_id
      }

      {:ok, _pid} = AppleMusic.SessionManager.start_link({user_id, user_session})

      conn =
        conn
        |> init_test_session(%{"user_id" => user_id, "auth_provider" => "apple_music"})
        |> fetch_flash()

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Signed in with Apple Music"
      assert html =~ "Sign Out"
      refute html =~ "Sign in"
    end

    test "LiveView handles missing Apple Music SessionManager gracefully", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{"user_id" => unique_user_id(), "auth_provider" => "apple_music"})
        |> fetch_flash()

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Sign in"
      refute html =~ "Sign Out"
    end
  end
end
