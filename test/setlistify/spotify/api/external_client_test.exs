defmodule Setlistify.Spotify.Api.ExternalClientTest do
  use Setlistify.DataCase, async: true

  alias Setlistify.Spotify.API.ExternalClient

  @user_profile_response fixture_dir()
                         |> Path.join("spotify_user_profile_response.json")
                         |> File.read!()

  setup do
    bypass = Bypass.open()
    client = ExternalClient.new("token", "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass, client: client}
  end

  test "username/1", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/me", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, @user_profile_response)
    end)

    assert ExternalClient.username(client) == "myusername"
  end

  describe "search_for_track/3" do
    test "returns the first matching track", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/search", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, @search_response)
      end)

      result = ExternalClient.search_for_track(client, "some artist", "some track")

      assert result.uri =~ ~r"spotify:track:\w+"
    end

    test "returns nil if no tracks are found", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/search", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"tracks" => %{"items" => []}}))
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert ExternalClient.search_for_track(client, "some artist", "some track") == nil
      end)
    end
  end
end
