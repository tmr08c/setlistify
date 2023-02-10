defmodule SetlistifyWeb.SearchLiveTest do
  use SetlistifyWeb.ConnCase

  import Phoenix.LiveViewTest

  test "searching for setlists", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")

    assert view |> element("form") |> render_submit(%{search: %{query: ""}}) =~
             "can&#39;t be blank"

    assert view |> element("form") |> render_submit(%{search: %{query: "the band"}}) =~
             ~r/searching for.*the band/i
  end
end
