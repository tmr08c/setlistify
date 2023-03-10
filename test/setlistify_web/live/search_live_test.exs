defmodule SetlistifyWeb.SearchLiveTest do
  use SetlistifyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hammox

  alias Setlistify.SetlistFm

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  test "searching for setlists", %{conn: conn} do
    defmock(SetlistFm.API.MockClient, for: SetlistFm.API)
    Application.put_env(:setlistify, :setlistfm_api_client, SetlistFm.API.MockClient)

    setlist_id = Ecto.UUID.generate()

    expect(SetlistFm.API.MockClient, :search, 1, fn "beatles" ->
      [
        %{
          artist: "The Beatles",
          venue: %{name: "Compaq Center"},
          date: Date.new!(2023, 01, 01),
          id: setlist_id
        }
      ]
    end)

    {:ok, view, _} = live(conn, ~p"/")

    assert view |> element("form") |> render_submit(%{search: %{query: ""}}) =~
             "can&#39;t be blank"

    html = assert view |> element("form") |> render_submit(%{search: %{query: "beatles"}})

    assert html =~ "The Beatles"
    assert html =~ "Compaq Center"
    assert html =~ "2023-01-01"

    view |> element(tid("setlist-#{setlist_id}")) |> render_click()
    assert_redirected(view, ~p"/setlists/#{setlist_id}")
  end
end
