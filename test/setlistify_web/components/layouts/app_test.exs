defmodule SetlistifyWeb.Layouts.AppTest do
  use SetlistifyWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "authentication UI elements" do
    test "displays sign in link when user is not authenticated", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Assert that the sign in link is shown
      assert has_element?(view, "a", "Sign in with Spotify")

      # When we click the link, we should be redirected to the Spotify OAuth flow
      # with the current page as the redirect_to
      signin_link = element(view, "a", "Sign in with Spotify")

      # The LiveView test doesn't follow external redirects automatically,
      # so we need to use assert_redirect to check the redirect
      render_click(signin_link)
      {path, _flash} = assert_redirect(view)
      assert path =~ "/signin/spotify"
      assert path =~ "redirect_to"
    end

    test "displays username and sign out link when user is authenticated", %{conn: conn} do
      # Create a conn with a user in the session
      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:access_token, "test_access_token")
        |> put_session(:account_name, "test_user")

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
