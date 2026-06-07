defmodule SetlistifyWeb.HomeLiveTest do
  use SetlistifyWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders hero section and how it works", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Hero headline contains key marketing text
    assert has_element?(view, "#hero-headline", "Transform")
    assert has_element?(view, "#hero-headline", "Live Shows")
    assert has_element?(view, "#hero-headline", "Playlists")
    assert has_element?(view, "#hero-headline", "One Click")

    # How It Works section
    assert has_element?(view, "#how-it-works", "How It Works")
    assert has_element?(view, "#how-it-works", "Search an Artist")
    assert has_element?(view, "#how-it-works", "Pick a Setlist")
    assert has_element?(view, "#how-it-works", "Create Playlist")
  end

  test "contains search form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "input[name='search[query]'][placeholder='Search for an artist or band...']")
  end
end
