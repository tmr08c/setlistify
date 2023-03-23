defmodule Setlistify.Spotify.Api.ExternalClientTest do
  use Setlistify.DataCase, async: true

  alias Setlistify.Spotify.API.ExternalClient

  setup do
    bypass = Bypass.open()
    client = ExternalClient.new("token", "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass, client: client}
  end

  test "username/1", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/me", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"display_name" => "my username"}))
    end)

    assert ExternalClient.username(client) == "my username"
  end

  @search_response fixture_dir()
                   |> Path.join("spotify_track_search_response.json")
                   |> File.read!()
  test "search_for_track/3", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/search", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, @search_response)
    end)

    result = ExternalClient.search_for_track(client, "some artist", "some track")

    assert result.uri =~ ~r"spotify:track:\w+"
  end
end
