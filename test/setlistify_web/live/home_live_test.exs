defmodule SetlistifyWeb.HomeLiveTest do
  use SetlistifyWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders hero section and how it works", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Transform"
    assert html =~ "Live Shows"
    assert html =~ "Playlists"
    assert html =~ "One Click"
    assert html =~ "How It Works"
    assert html =~ "Search an Artist"
    assert html =~ "Pick a Setlist"
    assert html =~ "Create Playlist"
  end

  test "contains search form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Search for an artist or band..."
    assert html =~ "name=\"search[query]\""
  end
end
