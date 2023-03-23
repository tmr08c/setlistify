defmodule Setlistify.SetlistFm.API.ExternalClientTest do
  use Setlistify.DataCase, async: true

  alias Setlistify.SetlistFm.API.ExternalClient

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  @search_response fixture_dir() |> Path.join("setlist_fm_search_response.json") |> File.read!()
  test "search/1", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/search/setlists", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, @search_response)
    end)

    [event | _] = result = ExternalClient.search("modest mouse", endpoint_url(bypass.port))

    assert length(result) == 20
    assert event.artist == "Modest Mouse"
    assert event.venue.name == "9:30 Club"
    assert event.date == Date.new!(2022, 12, 20)
    assert event.id
  end

  @get_response fixture_dir() |> Path.join("setlist_fm_setlist_response.json") |> File.read!()
  test "get_setlist/1", %{bypass: bypass} do
    id = Ecto.UUID.generate()

    Bypass.expect_once(bypass, "GET", "/setlist/#{id}", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, @get_response)
    end)

    result = ExternalClient.get_setlist(id, endpoint_url(bypass.port)) |> dbg()

    Enum.flat_map(result.sets, fn set ->
      {songs, set} = Map.pop(set, :songs)
      Enum.map(songs, &Map.merge(&1, set))
    end)
    |> Enum.group_by(&{&1.name, &1.encore})
    |> Enum.reverse()
    |> dbg()

    assert result.artist == "Modest Mouse"
    assert result.venue.name == "Terminal 5"
    assert result.date == Date.new!(2022, 12, 19)
    assert length(result.sets) == 3
    assert Enum.count(result.sets, & &1.encore) == 1

    for %{songs: songs} <- result.sets do
      assert length(songs) > 0
    end
  end

  defp endpoint_url(port), do: "http://localhost:#{port}"
end
