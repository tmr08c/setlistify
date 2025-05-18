defmodule SetlistifyWeb.SearchLiveTest do
  use SetlistifyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Hammox

  alias Setlistify.SetlistFm

  # Cache fetching happens in another process, managed by Cachex. The process we
  # start in our application tree is a supervisor, so explictly `allow`ing with
  # that PID does not work. This will enable "global" mode which means  any
  # process will respect our `expect` at the cost of not being able to run with
  # `async: true`
  setup :set_mox_from_context
  setup :verify_on_exit!

  test "searching for setlists", %{conn: conn} do
    setlist_id = Ecto.UUID.generate()

    expect(SetlistFm.API.MockClient, :search, 1, fn "beatles" ->
      [
        %{
          artist: "The Beatles",
          venue: %{
            name: "Compaq Center",
            location: %{city: "Houston", state: "TX", country: "United States"}
          },
          date: Date.new!(2023, 01, 01),
          id: setlist_id,
          song_count: 12
        }
      ]
    end)

    {:ok, view, _} = live(conn, ~p"/")

    assert view |> form("[name='search']", %{search: %{query: ""}}) |> render_submit() =~
             "can&#39;t be blank"

    html = view |> form("[name='search']", %{search: %{query: "beatles"}}) |> render_submit()

    assert html =~ "The Beatles"
    assert html =~ "Compaq Center"
    assert html =~ "Houston, TX, United States"
    assert html =~ "2023-01-01"

    view |> element(tid("setlist-#{setlist_id}")) |> render_click()
    assert_redirected(view, ~p"/setlist/#{setlist_id}")
  end

  test "displays song count in search results", %{conn: conn} do
    expect(SetlistFm.API.MockClient, :search, 1, fn "test artist" ->
      [
        %{
          artist: "Test Artist",
          venue: %{
            name: "Test Venue 1",
            location: %{city: "Austin", state: "TX", country: "United States"}
          },
          date: Date.new!(2023, 01, 01),
          id: "test-id-1",
          song_count: 0
        },
        %{
          artist: "Test Artist",
          venue: %{
            name: "Test Venue 2",
            location: %{city: "Seattle", state: "WA", country: "United States"}
          },
          date: Date.new!(2023, 01, 02),
          id: "test-id-2",
          song_count: 15
        },
        %{
          artist: "Test Artist",
          venue: %{
            name: "Test Venue 3",
            location: %{city: "Nashville", state: "TN", country: "United States"}
          },
          date: Date.new!(2023, 01, 03),
          id: "test-id-3",
          song_count: 1
        }
      ]
    end)

    {:ok, _view, html} = live(conn, ~p"/?query=test+artist")

    # Check that song counts are displayed
    assert html =~ "0 songs"
    assert html =~ "15 songs"
    assert html =~ "1 song"
  end
end
