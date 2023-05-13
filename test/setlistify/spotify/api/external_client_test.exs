defmodule Setlistify.Spotify.Api.ExternalClientTest do
  use Setlistify.DataCase, async: true

  alias Setlistify.Spotify.API.ExternalClient

  @user_profile_response fixture_dir()
                         |> Path.join("spotify_user_profile_response.json")
                         |> File.read!()

  @user_profile_user_id "myusername"

  @search_response fixture_dir()
                   |> Path.join("spotify_track_search_response.json")
                   |> File.read!()

  @create_playlist_response fixture_dir()
                            |> Path.join("spotify_create_playlist_response.json")
                            |> File.read!()

  @add_tracks_response fixture_dir()
                       |> Path.join("spotify_add_tracks_to_playlist_response.json")
                       |> File.read!()

  setup do
    bypass = Bypass.open()
    client = ExternalClient.new("token", "http://localhost:#{bypass.port}/")
    {:ok, bypass: bypass, client: client}
  end

  test "username/1", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/me", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, @user_profile_response)
    end)

    assert ExternalClient.username(client) == @user_profile_user_id
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

  describe "create_playlist/3" do
    test "creates a new playlist", %{bypass: bypass, client: client} do
      # TODO: Long-term I do not want to have to re-request the information and
      # instead would prefer for it to be stored in the system
      Bypass.expect_once(bypass, "GET", "/me", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, @user_profile_response)
      end)

      Bypass.expect_once(bypass, "POST", "/users/#{@user_profile_user_id}/playlists", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["name"] == "Test Playlist"
        assert payload["description"] == "Test Description"
        assert payload["public"] == false

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(201, @create_playlist_response)
      end)

      playlist_response =
        ExternalClient.create_playlist(client, "Test Playlist", "Test Description")

      assert playlist_response.id
      assert playlist_response.external_url =~ "open.spotify"
    end
  end

  describe "add_tracks_to_playlist/3" do
    test "adds tracks to a playlist", %{bypass: bypass, client: client} do
      track_uris = ["spotify:track:123", "spotify:track:456"]

      Bypass.expect_once(bypass, "POST", "/playlists/playlist123/tracks", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["uris"] == track_uris

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(201, @add_tracks_response)
      end)

      assert ExternalClient.add_tracks_to_playlist(client, "playlist123", track_uris) == :ok
    end

    test "handles empty track list gracefully", %{client: client} do
      assert ExternalClient.add_tracks_to_playlist(client, "playlist123", []) == :ok
    end
  end

  describe "get_embed/1" do
    test "returns embedded HTML on successful response" do
      url = "https://open.spotify.com/playlist/123"
      html = "<iframe src='spotify:embed:123'></iframe>"

      Req.Test.stub(MySpotifyStub, fn conn ->
        response = %{"html" => html}
        Req.Test.json(conn, response)
      end)

      assert {:ok, ^html} = ExternalClient.get_embed(url)
    end

    test "returns error on non-200 response" do
      url = "https://open.spotify.com/playlist/123"

      Req.Test.stub(MySpotifyStub, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      assert {:error, :failed_to_fetch} = ExternalClient.get_embed(url)
    end

    test "returns error on invalid response body" do
      url = "https://open.spotify.com/playlist/123"

      Req.Test.stub(MySpotifyStub, fn conn ->
        response = %{"not_html" => "something else"}
        Req.Test.json(conn, response)
      end)

      assert {:error, :invalid_response} = ExternalClient.get_embed(url)
    end
  end
end
