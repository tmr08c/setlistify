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
    Req.Test.verify_on_exit!()
    {:ok, client: ExternalClient.new("token")}
  end

  test "username/1", %{client: client} do
    Req.Test.stub(MySpotifyStub, fn
      %{request_path: "/v1/me", method: "GET"} = conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(Jason.decode!(@user_profile_response)))
    end)

    assert ExternalClient.username(client) == @user_profile_user_id
  end

  describe "search_for_track/3" do
    test "returns the first matching track", %{client: client} do
      Req.Test.stub(MySpotifyStub, fn
        %{request_path: "/v1/search", method: "GET"} = conn ->
          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(Jason.decode!(@search_response)))
      end)

      result = ExternalClient.search_for_track(client, "some artist", "some track")

      assert result.uri =~ ~r"spotify:track:\w+"
    end

    test "returns nil if no tracks are found", %{client: client} do
      Req.Test.stub(MySpotifyStub, fn
        %{request_path: "/v1/search", method: "GET"} = conn ->
          response = %{"tracks" => %{"items" => []}}

          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(response))
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert ExternalClient.search_for_track(client, "some artist", "some track") == nil
      end)
    end
  end

  describe "create_playlist/3" do
    test "creates a new playlist", %{client: client} do
      # TODO: Long-term I do not want to have to re-request the information and
      # instead would prefer for it to be stored in the system
      Req.Test.stub(MySpotifyStub, fn
        %{request_path: "/v1/me", method: "GET"} = conn ->
          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(Jason.decode!(@user_profile_response)))

        %{request_path: "/v1/users/" <> rest, method: "POST"} = conn ->
          assert rest =~ ~r"^#{@user_profile_user_id}/playlists"

          # Assert the request payload is correct
          {:ok, body, _} = Plug.Conn.read_body(conn)

          assert Jason.decode!(body) == %{
                   "name" => "Test Playlist",
                   "description" => "Test Description",
                   "public" => false
                 }

          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.send_resp(201, Jason.encode!(Jason.decode!(@create_playlist_response)))
      end)

      playlist_response =
        ExternalClient.create_playlist(client, "Test Playlist", "Test Description")

      assert playlist_response.id
      assert playlist_response.external_url =~ "open.spotify"
    end
  end

  describe "add_tracks_to_playlist/3" do
    test "adds tracks to a playlist", %{client: client} do
      track_uris = ["spotify:track:123", "spotify:track:456"]

      Req.Test.stub(MySpotifyStub, fn
        %{request_path: "/v1/playlists/" <> rest, method: "POST"} = conn ->
          assert rest =~ ~r"^playlist123/tracks"

          # Assert the request payload contains the track URIs
          {:ok, body, _} = Plug.Conn.read_body(conn)

          assert Jason.decode!(body) == %{
                   "uris" => track_uris
                 }

          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.send_resp(201, Jason.encode!(Jason.decode!(@add_tracks_response)))
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

  # TODO: Pick up here: Working to make tests pass
  # Just got the success case to work, need to clean up logging
  # then need to find other places where manually refreshing or in diff where now
  # using this function, but mocking Req and not the function
  describe "refresh_token/1" do
    test "successfully refreshes token with new refresh token" do
      Req.Test.expect(
        MySpotifyStub,
        fn conn ->
          # Verify auth header format
          assert ["Basic " <> _token] = Plug.Conn.get_req_header(conn, "authorization")
          {:ok, body, _} = Plug.Conn.read_body(conn)

          assert URI.decode_query(body) == %{
                   "grant_type" => "refresh_token",
                   "refresh_token" => "old_refresh_token"
                 }

          response = %{
            "access_token" => "new_access_token",
            "refresh_token" => "new_refresh_token",
            "expires_in" => 3600
          }

          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(response))
        end
      )

      assert {:ok, tokens} = ExternalClient.refresh_token("old_refresh_token")
      assert tokens.access_token == "new_access_token"
      assert tokens.refresh_token == "new_refresh_token"
      assert tokens.expires_in == 3600
    end

    test "successfully refreshes token keeping existing refresh token" do
      Req.Test.expect(
        MySpotifyStub,
        fn conn ->
          {:ok, body, _} = Plug.Conn.read_body(conn)

          assert URI.decode_query(body) == %{
                   "grant_type" => "refresh_token",
                   "refresh_token" => "old_refresh_token"
                 }

          # This does **not** include the refresh token, so we expect to keep
          # using our old refresh token
          response = %{
            "access_token" => "new_access_token",
            "expires_in" => 3600
          }

          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(response))
        end
      )

      assert {:ok, tokens} = ExternalClient.refresh_token("old_refresh_token")
      assert tokens.access_token == "new_access_token"
      # Should keep old token when none provided
      assert tokens.refresh_token == "old_refresh_token"
      assert tokens.expires_in == 3600
    end

    test "returns error on invalid token" do
      Req.Test.expect(MySpotifyStub, fn conn -> Plug.Conn.send_resp(conn, 401, "Unauthorized") end)

      assert {:error, :invalid_token} = ExternalClient.refresh_token("invalid_token")
    end

    test "returns error on bad request" do
      Req.Test.expect(MySpotifyStub, fn conn -> Plug.Conn.send_resp(conn, 400, "Bad Request") end)

      assert {:error, :invalid_token} = ExternalClient.refresh_token("bad_token")
    end

    test "returns error on server error" do
      Req.Test.expect(MySpotifyStub, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      assert {:error, _} = ExternalClient.refresh_token("some_token")
    end
  end
end
