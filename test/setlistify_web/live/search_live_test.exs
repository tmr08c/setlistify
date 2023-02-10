defmodule SetlistifyWeb.SearchLiveTest do
  use SetlistifyWeb.ConnCase

  import Phoenix.LiveViewTest

  test "searching for setlists", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/")

    assert html =~ "Hello"
  end
end
