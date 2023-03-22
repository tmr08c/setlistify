defmodule SetlistifyWeb.Setlists.ShowLiveTest do
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

  test "viewing a setlist", %{conn: conn} do
    setlist_id = Ecto.UUID.generate()

    expect(SetlistFm.API.MockClient, :get_setlist, 1, fn ^setlist_id ->
      %{
        artist: "The Beatles",
        venue: %{name: "Compaq Center"},
        date: Date.new!(2023, 01, 01),
        sets: [
          %{name: "Warm up", songs: ["a warm up song"]},
          %{name: nil, songs: ["main set song1", "main set song2"]},
          %{name: nil, encore: 1, songs: ["encore song1", "encore song2"]}
        ]
      }
    end)

    {:ok, _view, html} = live(conn, ~p"/setlist/#{setlist_id}")

    assert html =~ "warm up"
    assert html =~ "a warm up song"

    assert html =~ "main set song1"
    assert html =~ "main set song2"

    assert html =~ "Encore 1"
    assert html =~ "encore song1"
    assert html =~ "encore song2"
  end
end
