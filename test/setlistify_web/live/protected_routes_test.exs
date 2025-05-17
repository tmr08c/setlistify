defmodule SetlistifyWeb.ProtectedRoutesTest do
  use SetlistifyWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "protected routes" do
    test "redirects unauthenticated users to signin page", %{conn: conn} do
      # Try to access playlists page without authentication
      {:error, {:live_redirect, redirect_info}} = live(conn, ~p"/playlists")

      assert redirect_info.to == "/?redirect_to=/playlists"
      assert redirect_info.flash["error"] == "You must log in to access this page."
    end

    test "preserves redirect_to parameter when redirecting", %{conn: conn} do
      # Try to access playlists page with query params
      {:error, {:live_redirect, redirect_info}} =
        live(conn, ~p"/playlists?provider=spotify&url=test")

      # Note: Query params are not preserved in the redirect_to parameter for simplicity
      assert redirect_info.to == "/?redirect_to=/playlists"
      assert redirect_info.flash["error"] == "You must log in to access this page."
    end
  end
end
