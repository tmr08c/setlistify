defmodule Setlistify.SetlistFm.API.ExternalClientTest do
  use Setlistify.DataCase, async: true

  alias Setlistify.SetlistFm.API.ExternalClient

  @response Path.join([
              File.cwd!(),
              "test",
              "support",
              "fixtures",
              "setlist_fm_search_response.json"
            ])
            |> File.read!()

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  test "search/1", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/search/setlists", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, @response)
    end)

    [event | _] = result = ExternalClient.search("modest mouse", endpoint_url(bypass.port))

    assert length(result) == 20
    assert event.artist == "Modest Mouse"
    assert event.venue.name == "9:30 Club"
    assert event.date == Date.new!(2022, 12, 20)
  end

  defp endpoint_url(port), do: "http://localhost:#{port}"
end
