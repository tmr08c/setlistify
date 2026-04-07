defmodule Setlistify.AppleMusic.API.ExternalClientTest do
  # async: false required because DeveloperTokenManager is a named process
  use Setlistify.DataCase, async: false

  alias Setlistify.AppleMusic.API.ExternalClient
  alias Setlistify.AppleMusic.DeveloperTokenManager
  alias Setlistify.AppleMusic.UserSession

  @test_private_pem """
  -----BEGIN PRIVATE KEY-----
  MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgPPtyY/6NgUDDyUOn
  X2sk64l0Mi4VQjc7pP/MpCvgLv+hRANCAAQN5Qh4TCaEdgmH2zjTZaIR8Pten3mw
  152R0P9vLEzTqu7g8GEK0G9Jlj9EhXl6xUxI/RlStMOsrNVBqRefSxZC
  -----END PRIVATE KEY-----
  """

  @search_response fixture_dir()
                   |> Path.join("apple_music_track_search_response.json")
                   |> File.read!()

  @create_playlist_response fixture_dir()
                            |> Path.join("apple_music_create_playlist_response.json")
                            |> File.read!()

  @user_session %UserSession{
    user_token: "test_user_token",
    user_id: "test-user-id",
    storefront: "us"
  }

  setup do
    Req.Test.verify_on_exit!()

    Application.put_env(:setlistify, :apple_music_team_id, "TEST_TEAM_ID")
    Application.put_env(:setlistify, :apple_music_key_id, "TEST_KEY_ID")
    Application.put_env(:setlistify, :apple_music_private_key, @test_private_pem)

    on_exit(fn ->
      Application.delete_env(:setlistify, :apple_music_team_id)
      Application.delete_env(:setlistify, :apple_music_key_id)
      Application.delete_env(:setlistify, :apple_music_private_key)
    end)

    start_supervised!(DeveloperTokenManager)
    :ok
  end

  describe "search_for_track/3" do
    test "returns a track_id for a matching track" do
      Req.Test.stub(MyAppleMusicStub, fn
        %{request_path: "/v1/catalog/us/search"} = conn ->
          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.send_resp(200, @search_response)
      end)

      assert %{track_id: track_id} =
               ExternalClient.search_for_track(@user_session, "The Beatles", "Come Together")

      assert is_binary(track_id)
      assert track_id =~ ~r/^\d+$/
    end

    test "returns nil when no tracks are found" do
      Req.Test.stub(MyAppleMusicStub, fn
        %{request_path: "/v1/catalog/us/search"} = conn ->
          response = %{"results" => %{"songs" => %{"data" => []}}}
          Req.Test.json(conn, response)
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert ExternalClient.search_for_track(@user_session, "Unknown", "Unknown") == nil
      end)
    end

    test "retries with refreshed developer token on 401 and succeeds" do
      Req.Test.expect(MyAppleMusicStub, fn conn ->
        Plug.Conn.send_resp(conn, 401, "Unauthorized")
      end)

      Req.Test.expect(MyAppleMusicStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, @search_response)
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert %{track_id: track_id} =
                 ExternalClient.search_for_track(@user_session, "The Beatles", "Come Together")

        assert track_id =~ ~r/^\d+$/
      end)
    end

    test "returns error when still unauthorized after retry" do
      Req.Test.expect(MyAppleMusicStub, fn conn ->
        Plug.Conn.send_resp(conn, 401, "Unauthorized")
      end)

      Req.Test.expect(MyAppleMusicStub, fn conn ->
        Plug.Conn.send_resp(conn, 401, "Unauthorized")
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :unauthorized} =
                 ExternalClient.search_for_track(@user_session, "Artist", "Track")
      end)
    end
  end

  describe "create_playlist/3" do
    test "creates a playlist and returns id and external_url" do
      Req.Test.stub(MyAppleMusicStub, fn
        %{request_path: "/v1/me/library/playlists", method: "POST"} = conn ->
          {:ok, body, _} = Plug.Conn.read_body(conn)

          assert Jason.decode!(body) == %{
                   "attributes" => %{
                     "name" => "My Playlist",
                     "description" => "A description"
                   }
                 }

          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.send_resp(201, @create_playlist_response)
      end)

      assert {:ok, %{id: id, external_url: external_url}} =
               ExternalClient.create_playlist(@user_session, "My Playlist", "A description")

      assert is_binary(id)
      assert external_url == "https://music.apple.com/library/playlist/#{id}"
    end

    test "returns error on unexpected status" do
      Req.Test.stub(MyAppleMusicStub, fn
        %{request_path: "/v1/me/library/playlists", method: "POST"} = conn ->
          Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :playlist_creation_failed} =
                 ExternalClient.create_playlist(@user_session, "My Playlist", "A description")
      end)
    end

    @tag :capture_log
    test "retries with refreshed developer token on 401 and succeeds" do
      Req.Test.expect(MyAppleMusicStub, fn conn ->
        Plug.Conn.send_resp(conn, 401, "Unauthorized")
      end)

      Req.Test.expect(MyAppleMusicStub, fn
        %{request_path: "/v1/me/library/playlists", method: "POST"} = conn ->
          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.send_resp(201, @create_playlist_response)
      end)

      assert {:ok, %{id: id}} =
               ExternalClient.create_playlist(@user_session, "My Playlist", "A description")

      assert is_binary(id)
    end

    @tag :capture_log
    test "returns error when still unauthorized after retry" do
      Req.Test.expect(MyAppleMusicStub, fn conn ->
        Plug.Conn.send_resp(conn, 401, "Unauthorized")
      end)

      Req.Test.expect(MyAppleMusicStub, fn conn ->
        Plug.Conn.send_resp(conn, 401, "Unauthorized")
      end)

      assert {:error, :unauthorized} =
               ExternalClient.create_playlist(@user_session, "My Playlist", "A description")
    end
  end

  describe "add_tracks_to_playlist/3" do
    test "returns :no_tracks immediately for empty list" do
      assert {:ok, :no_tracks} =
               ExternalClient.add_tracks_to_playlist(@user_session, "p.abc123", [])
    end

    test "adds tracks to the correct playlist and returns :tracks_added on 204" do
      Req.Test.stub(MyAppleMusicStub, fn
        %{request_path: "/v1/me/library/playlists/p.abc123/tracks", method: "POST"} = conn ->
          {:ok, body, _} = Plug.Conn.read_body(conn)
          data = Jason.decode!(body)["data"]
          assert length(data) == 2
          assert Enum.all?(data, &(&1["type"] == "songs"))
          Plug.Conn.send_resp(conn, 204, "")
      end)

      assert {:ok, :tracks_added} =
               ExternalClient.add_tracks_to_playlist(
                 @user_session,
                 "p.abc123",
                 ["1441164430", "1440857781"]
               )
    end

    test "returns error on unexpected status" do
      Req.Test.stub(MyAppleMusicStub, fn
        %{request_path: "/v1/me/library/playlists/p.abc123/tracks", method: "POST"} = conn ->
          Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :tracks_addition_failed} =
                 ExternalClient.add_tracks_to_playlist(
                   @user_session,
                   "p.abc123",
                   ["1441164430"]
                 )
      end)
    end

    @tag :capture_log
    test "retries with refreshed developer token on 401 and succeeds" do
      Req.Test.expect(MyAppleMusicStub, fn conn ->
        Plug.Conn.send_resp(conn, 401, "Unauthorized")
      end)

      Req.Test.expect(MyAppleMusicStub, fn conn ->
        Plug.Conn.send_resp(conn, 204, "")
      end)

      assert {:ok, :tracks_added} =
               ExternalClient.add_tracks_to_playlist(
                 @user_session,
                 "p.abc123",
                 ["1441164430"]
               )
    end

    @tag :capture_log
    test "returns error when still unauthorized after retry" do
      Req.Test.expect(MyAppleMusicStub, fn conn ->
        Plug.Conn.send_resp(conn, 401, "Unauthorized")
      end)

      Req.Test.expect(MyAppleMusicStub, fn conn ->
        Plug.Conn.send_resp(conn, 401, "Unauthorized")
      end)

      assert {:error, :unauthorized} =
               ExternalClient.add_tracks_to_playlist(
                 @user_session,
                 "p.abc123",
                 ["1441164430"]
               )
    end
  end
end
