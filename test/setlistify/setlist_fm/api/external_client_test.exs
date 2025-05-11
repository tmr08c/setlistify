defmodule Setlistify.SetlistFm.API.ExternalClientTest do
  use Setlistify.DataCase, async: true

  alias Setlistify.SetlistFm.API.ExternalClient

  setup do
    Req.Test.verify_on_exit!()
    :ok
  end

  @search_response fixture_dir() |> Path.join("setlist_fm_search_response.json") |> File.read!()
  test "search/1" do
    Req.Test.stub(MySetlistFmStub, fn
      %{request_path: "/rest/1.0/search/setlists", method: "GET"} = conn ->
        assert conn.params["artistName"] == "modest mouse"

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(Jason.decode!(@search_response)))
    end)

    [event | _] = result = ExternalClient.search("modest mouse")

    assert length(result) == 20
    assert event.artist == "Modest Mouse"
    assert event.venue.name == "9:30 Club"
    assert event.date == Date.new!(2022, 12, 20)
    assert event.id
  end

  @get_response fixture_dir() |> Path.join("setlist_fm_setlist_response.json") |> File.read!()
  test "get_setlist/1" do
    id = Ecto.UUID.generate()

    Req.Test.stub(MySetlistFmStub, fn %{request_path: "/rest/1.0/setlist/" <> rest, method: "GET"} =
                                        conn ->
      assert rest == id

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(Jason.decode!(@get_response)))
    end)

    result = ExternalClient.get_setlist(id)

    assert result.artist == "Modest Mouse"
    assert result.venue.name == "Terminal 5"
    assert result.date == Date.new!(2022, 12, 19)
    assert length(result.sets) == 3
    assert Enum.count(result.sets, & &1.encore) == 1

    for %{songs: songs} <- result.sets do
      assert length(songs) > 0
    end
  end
end
