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

    test "rejects results whose artist does not match the queried artist" do
      # Mimics Apple Music returning an unrelated top-1 result when the
      # queried artist never matches anywhere in the catalog (e.g. searching
      # "Tim Kasher From the Hips" and getting back a Labrinth song).
      Req.Test.stub(MyAppleMusicStub, fn
        %{request_path: "/v1/catalog/us/search"} = conn ->
          Req.Test.json(conn, %{
            "results" => %{
              "songs" => %{
                "data" => [
                  %{
                    "id" => "12345",
                    "type" => "songs",
                    "attributes" => %{
                      "artistName" => "Labrinth",
                      "name" => "Still Don't Know My Name"
                    }
                  }
                ]
              }
            }
          })
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert ExternalClient.search_for_track(@user_session, "Tim Kasher", "From the Hips") ==
                 nil
      end)
    end

    test "falls back to cover artist when performing artist returns no usable match" do
      # Performing artist call returns no usable result, cover artist call hits.
      Req.Test.expect(MyAppleMusicStub, fn %{query_string: qs} = conn ->
        assert qs =~ "term=Tim+Kasher+Driftwood"
        Req.Test.json(conn, %{"results" => %{"songs" => %{"data" => []}}})
      end)

      Req.Test.expect(MyAppleMusicStub, fn %{query_string: qs} = conn ->
        assert qs =~ "term=Cursive+Driftwood"

        Req.Test.json(conn, %{
          "results" => %{
            "songs" => %{
              "data" => [
                %{
                  "id" => "1187475400",
                  "type" => "songs",
                  "attributes" => %{
                    "artistName" => "Cursive",
                    "name" => "Driftwood: A Fairy Tale"
                  }
                }
              ]
            }
          }
        })
      end)

      assert %{track_id: "1187475400"} =
               ExternalClient.search_for_track(
                 @user_session,
                 "Tim Kasher",
                 "Driftwood: A Fairy Tale",
                 "Cursive"
               )
    end

    test "returns nil when the cover artist fallback also returns a mismatched artist" do
      # Performing-artist search misses, cover-artist fallback fires but the
      # top-1 result is again from an unrelated artist — verify we don't slip
      # through and return the bad fallback result.
      Req.Test.expect(MyAppleMusicStub, fn %{query_string: qs} = conn ->
        assert qs =~ "term=Tim+Kasher+Driftwood"
        Req.Test.json(conn, %{"results" => %{"songs" => %{"data" => []}}})
      end)

      Req.Test.expect(MyAppleMusicStub, fn %{query_string: qs} = conn ->
        assert qs =~ "term=Cursive+Driftwood"

        Req.Test.json(conn, %{
          "results" => %{
            "songs" => %{
              "data" => [
                %{
                  "id" => "99999",
                  "type" => "songs",
                  "attributes" => %{
                    "artistName" => "Some Other Artist",
                    "name" => "Driftwood"
                  }
                }
              ]
            }
          }
        })
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert ExternalClient.search_for_track(
                 @user_session,
                 "Tim Kasher",
                 "Driftwood: A Fairy Tale",
                 "Cursive"
               ) == nil
      end)
    end

    test "propagates primary search error without attempting cover artist fallback" do
      # After with_developer_token_refresh exhausts its retry, an unauthorized
      # error should bubble up — we should NOT try the cover_artist with a
      # presumably-still-broken auth context.
      #
      # Both expected requests query the primary artist ("Tim Kasher"): the
      # first is the initial call, the second is the token-refresh retry
      # inside with_developer_token_refresh. Neither should query "Cursive" —
      # if the fallback wrongly fired we'd see a third request, and the
      # assertions below would also catch a Cursive query in slot 2.
      Req.Test.expect(MyAppleMusicStub, fn %{query_string: qs} = conn ->
        assert qs =~ "term=Tim+Kasher+Driftwood"
        Plug.Conn.send_resp(conn, 401, "Unauthorized")
      end)

      Req.Test.expect(MyAppleMusicStub, fn %{query_string: qs} = conn ->
        assert qs =~ "term=Tim+Kasher+Driftwood"
        Plug.Conn.send_resp(conn, 401, "Unauthorized")
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :unauthorized} =
                 ExternalClient.search_for_track(
                   @user_session,
                   "Tim Kasher",
                   "Driftwood: A Fairy Tale",
                   "Cursive"
                 )
      end)
    end

    test "uses performing artist first when it matches, without calling cover artist" do
      # Only the performing-artist call is expected; if a fallback fires the
      # test fails because Req.Test.verify_on_exit! sees an unconsumed expect.
      Req.Test.expect(MyAppleMusicStub, fn %{query_string: qs} = conn ->
        assert qs =~ "term=Cursive+The+Recluse"

        Req.Test.json(conn, %{
          "results" => %{
            "songs" => %{
              "data" => [
                %{
                  "id" => "9999",
                  "type" => "songs",
                  "attributes" => %{"artistName" => "Cursive", "name" => "The Recluse"}
                }
              ]
            }
          }
        })
      end)

      assert %{track_id: "9999"} =
               ExternalClient.search_for_track(
                 @user_session,
                 "Cursive",
                 "The Recluse",
                 "Some Other Band"
               )
    end
  end

  describe "create_playlist/3" do
    test "creates a playlist and returns id and external_url" do
      Req.Test.stub(MyAppleMusicStub, fn
        %{request_path: "/v1/me/library/playlists", method: "POST"} = conn ->
          {:ok, body, _} = Plug.Conn.read_body(conn)

          assert JSON.decode!(body) == %{
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
          data = JSON.decode!(body)["data"]
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
