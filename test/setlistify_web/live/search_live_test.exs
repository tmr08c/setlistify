defmodule SetlistifyWeb.SearchLiveTest do
  use SetlistifyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hammox

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  test "searching for setlists", %{conn: conn} do
    defmock(Setlistify.SetlistFm.API.MockClient, for: Setlistify.SetlistFm.API)
    Application.put_env(:setlistify, :setlistfm_api_client, Setlistify.SetlistFm.API.MockClient)

    expect(Setlistify.SetlistFm.API.MockClient, :search, fn _ ->
      [%{artist: "The Beatles", venue: %{name: "Compaq Center"}, date: Date.new!(2023, 01, 01)}]
    end)

    {:ok, view, _} = live(conn, ~p"/")

    assert view |> element("form") |> render_submit(%{search: %{query: ""}}) =~
             "can&#39;t be blank"

    html = assert view |> element("form") |> render_submit(%{search: %{query: "beatles"}})

    assert html =~ "The Beatles"
    assert html =~ "Compaq Center"
    assert html =~ "2023-01-01"
  end
end
