defmodule Setlistify.AppleMusic.Api.ExternalClientTest do
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

  describe "build_user_session/3" do
    test "returns a UserSession struct" do
      assert {:ok, %UserSession{} = session} =
               ExternalClient.build_user_session("token", "us", "user-123")

      assert session.user_token == "token"
      assert session.storefront == "us"
      assert session.user_id == "user-123"
    end
  end

  describe "search_for_track/3" do
    test "returns the first matching track" do
      Req.Test.stub(MyAppleMusicStub, fn
        %{request_path: "/v1/catalog/us/search"} = conn ->
          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.send_resp(200, @search_response)
      end)

      assert %{track_id: "1441164430"} =
               ExternalClient.search_for_track(@user_session, "The Beatles", "Come Together")
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
        assert %{track_id: "1441164430"} =
                 ExternalClient.search_for_track(@user_session, "The Beatles", "Come Together")
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

      assert {:ok, %{id: "p.eoGxR1btAYexmB", external_url: external_url}} =
               ExternalClient.create_playlist(@user_session, "My Playlist", "A description")

      assert external_url == "https://music.apple.com/library/playlist/p.eoGxR1btAYexmB"
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

      assert {:ok, %{id: "p.eoGxR1btAYexmB"}} =
               ExternalClient.create_playlist(@user_session, "My Playlist", "A description")
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

    test "adds tracks and returns :tracks_added on 204" do
      Req.Test.stub(MyAppleMusicStub, fn
        %{request_path: "/v1/me/library/playlists/" <> _, method: "POST"} = conn ->
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
        %{request_path: "/v1/me/library/playlists/" <> _, method: "POST"} = conn ->
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

  describe "get_embed/1" do
    test "returns iframe HTML with embed URL" do
      url = "https://music.apple.com/us/playlist/my-playlist/pl.abc123"

      assert {:ok, html} = ExternalClient.get_embed(url)
      assert html =~ "https://embed.music.apple.com/us/playlist/my-playlist/pl.abc123"
      assert html =~ "<iframe"
      assert html =~ "autoplay *; encrypted-media *; fullscreen *;"
    end
  end
end
