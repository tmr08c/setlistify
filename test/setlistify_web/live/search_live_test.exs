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
          venue: %{name: "Compaq Center"},
          date: Date.new!(2023, 01, 01),
          id: setlist_id
        }
      ]
    end)

    {:ok, view, _} = live(conn, ~p"/")

    assert view |> form("[name='search']", %{search: %{query: ""}}) |> render_submit() =~
             "can&#39;t be blank"

    html = view |> form("[name='search']", %{search: %{query: "beatles"}}) |> render_submit()

    assert html =~ "The Beatles"
    assert html =~ "Compaq Center"
    assert html =~ "2023-01-01"

    view |> element(tid("setlist-#{setlist_id}")) |> render_click()
    assert_redirected(view, ~p"/setlist/#{setlist_id}")
  end
end
