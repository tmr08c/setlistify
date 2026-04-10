defmodule SetlistifyWeb.Layouts.AppTest do
  use SetlistifyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Setlistify.Spotify.SessionManager
  alias Setlistify.Spotify.UserSession

  describe "authentication UI elements" do
    test "displays sign in links when user is not authenticated", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "Spotify"
      assert has_element?(view, "a[title='Sign in with Spotify']")

      render_click(element(view, "a[title='Sign in with Spotify']"))
      {path, _flash} = assert_redirect(view)
      assert path =~ "/signin/spotify"
      assert path =~ "redirect_to"
    end

    test "displays sign out link when user is authenticated", %{conn: conn} do
      user_id = unique_user_id()

      # Create a UserSession for the test
      user_session = %UserSession{
        access_token: "token",
        refresh_token: "refresh_token",
        expires_at: System.system_time(:second) + 3600,
        user_id: user_id,
        username: "test_user"
      }

      # Start a SessionManager for the test user
      {:ok, _pid} = SessionManager.start_link({user_id, user_session})

      # Create a conn with a user in the session
      conn =
        conn
        |> init_test_session(%{})
        |> put_session("user_id", user_id)
        |> put_session("auth_provider", "spotify")

      {:ok, view, html} = live(conn, ~p"/")

      # Assert that the user's name is displayed
      assert html =~ "Signed in as test_user"

      # Assert that the sign out link is displayed
      assert has_element?(view, "a", "Sign Out")

      # When we click the link, we should be redirected to the sign out path
      signout_link = element(view, "a", "Sign Out")

      # Verify the redirect
      render_click(signout_link)
      {path, _flash} = assert_redirect(view)
      assert path == "/signout"
    end
  end
end
