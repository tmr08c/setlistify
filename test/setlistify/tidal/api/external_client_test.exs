defmodule Setlistify.Tidal.Api.ExternalClientTest do
  use Setlistify.DataCase, async: true

  import Hammox

  alias Setlistify.Tidal.API.ExternalClient
  alias Setlistify.Tidal.API.MockClient
  alias Setlistify.Tidal.RequestThrottle
  alias Setlistify.Tidal.SessionSupervisor
  alias Setlistify.Tidal.UserSession

  @user_id "12345"
  @country_code "US"
  @json_api_content_type "application/vnd.api+json"

  setup do
    Req.Test.verify_on_exit!()
    start_supervised!(RequestThrottle)

    user_session = %UserSession{
      access_token: "token",
      refresh_token: "refresh_token",
      expires_at: System.system_time(:second) + 14_400,
      user_id: @user_id,
      country_code: @country_code
    }

    {:ok, user_session: user_session}
  end

  # Builds a JSON:API search response body. Track references live under
  # data.relationships.tracks.data; the track and artist resources arrive in a
  # single flat top-level `included` list.
  defp search_response(tracks) do
    track_resources =
      Enum.map(tracks, fn track ->
        %{
          "id" => track.id,
          "type" => "tracks",
          "attributes" => %{"title" => track.title},
          "relationships" => %{
            "artists" => %{
              "data" => Enum.map(track.artists, &%{"id" => &1.id, "type" => "artists"})
            }
          }
        }
      end)

    artist_resources =
      tracks
      |> Enum.flat_map(& &1.artists)
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(&%{"id" => &1.id, "type" => "artists", "attributes" => %{"name" => &1.name}})

    %{
      "data" => %{
        "id" => "search-query-id",
        "type" => "searchResults",
        "relationships" => %{
          "tracks" => %{"data" => Enum.map(tracks, &%{"id" => &1.id, "type" => "tracks"})}
        }
      },
      "included" => track_resources ++ artist_resources
    }
  end

  defp json_api_resp(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "#{@json_api_content_type}; charset=utf-8")
    |> Plug.Conn.send_resp(status, JSON.encode!(body))
  end

  # A syntactically valid JWT carrying the given claims in its payload — the
  # signature is not verified by the client, so a placeholder segment is fine.
  defp jwt(claims) do
    header = Base.url_encode64(JSON.encode!(%{"alg" => "ES256", "typ" => "JWT"}), padding: false)
    payload = Base.url_encode64(JSON.encode!(claims), padding: false)

    "#{header}.#{payload}.placeholder-signature"
  end

  describe "search_for_track/4" do
    test "returns the first matching track resolved through included", %{user_session: user_session} do
      Req.Test.stub(MyTidalStub, fn %{method: "GET"} = conn ->
        assert conn.request_path =~ "/v2/searchResults/Modest%20Mouse%20Lace%20Your%20Shoes"

        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["countryCode"] == @country_code
        assert conn.query_params["include"] == "tracks,tracks.artists"

        json_api_resp(
          conn,
          200,
          search_response([
            %{id: "251380837", title: "Lace Your Shoes", artists: [%{id: "9x1", name: "Modest Mouse"}]}
          ])
        )
      end)

      assert %{track_id: "251380837"} =
               ExternalClient.search_for_track(user_session, "Modest Mouse", "Lace Your Shoes")
    end

    test "returns nil when the search has no results", %{user_session: user_session} do
      Req.Test.stub(MyTidalStub, fn conn ->
        json_api_resp(conn, 200, search_response([]))
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert ExternalClient.search_for_track(user_session, "some artist", "some track") == nil
      end)
    end

    test "returns nil when the response carries no relationships at all", %{user_session: user_session} do
      Req.Test.stub(MyTidalStub, fn conn ->
        json_api_resp(conn, 200, %{"data" => %{"id" => "q", "type" => "searchResults"}})
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert ExternalClient.search_for_track(user_session, "some artist", "some track") == nil
      end)
    end

    test "rejects results whose artist does not match the queried artist", %{user_session: user_session} do
      Req.Test.stub(MyTidalStub, fn conn ->
        json_api_resp(
          conn,
          200,
          search_response([
            %{id: "77", title: "Still Don't Know My Name", artists: [%{id: "a1", name: "Labrinth"}]}
          ])
        )
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert ExternalClient.search_for_track(user_session, "Tim Kasher", "From the Hips") == nil
      end)
    end

    test "treats an artist reference missing from included as a mismatch", %{user_session: user_session} do
      Req.Test.stub(MyTidalStub, fn conn ->
        body = search_response([%{id: "88", title: "From the Hips", artists: []}])

        # The track references an artist that never appears in `included`.
        body =
          put_in(
            body,
            ["included", Access.at(0), "relationships", "artists", "data"],
            [%{"id" => "missing-artist", "type" => "artists"}]
          )

        json_api_resp(conn, 200, body)
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert ExternalClient.search_for_track(user_session, "Tim Kasher", "From the Hips") == nil
      end)
    end

    test "falls back to cover artist when performing artist returns no usable match",
         %{user_session: user_session} do
      Req.Test.expect(MyTidalStub, fn conn ->
        assert conn.request_path =~ "Tim%20Kasher"
        json_api_resp(conn, 200, search_response([]))
      end)

      Req.Test.expect(MyTidalStub, fn conn ->
        assert conn.request_path =~ "Cursive"

        json_api_resp(
          conn,
          200,
          search_response([
            %{id: "cursive1", title: "Driftwood: A Fairy Tale", artists: [%{id: "c1", name: "Cursive"}]}
          ])
        )
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert %{track_id: "cursive1"} =
                 ExternalClient.search_for_track(
                   user_session,
                   "Tim Kasher",
                   "Driftwood: A Fairy Tale",
                   "Cursive"
                 )
      end)
    end

    test "propagates primary search error without attempting cover artist fallback",
         %{user_session: user_session} do
      Req.Test.expect(MyTidalStub, fn conn ->
        assert conn.request_path =~ "Tim%20Kasher"
        refute conn.request_path =~ "Cursive"
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :unexpected_response} =
                 ExternalClient.search_for_track(
                   user_session,
                   "Tim Kasher",
                   "Driftwood: A Fairy Tale",
                   "Cursive"
                 )
      end)
    end

    test "surfaces a 429 as {:error, {:rate_limited, retry_after}}", %{user_session: user_session} do
      Req.Test.expect(MyTidalStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "4")
        |> Plug.Conn.send_resp(429, "")
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, {:rate_limited, 4}} =
                 ExternalClient.search_for_track(user_session, "Modest Mouse", "Dramamine", "Cursive")
      end)
    end

    test "rate limited response without a retry-after header yields nil retry hint",
         %{user_session: user_session} do
      Req.Test.expect(MyTidalStub, fn conn ->
        Plug.Conn.send_resp(conn, 429, "")
      end)

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, {:rate_limited, nil}} =
                 ExternalClient.search_for_track(user_session, "Modest Mouse", "Dramamine")
      end)
    end
  end

  describe "create_playlist/3" do
    test "creates an UNLISTED playlist with a JSON:API body and idempotency key",
         %{user_session: user_session} do
      Req.Test.stub(MyTidalStub, fn %{method: "POST"} = conn ->
        assert conn.request_path == "/v2/playlists"

        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["countryCode"] == @country_code

        assert [@json_api_content_type <> _] = Plug.Conn.get_req_header(conn, "content-type")
        assert [idempotency_key] = Plug.Conn.get_req_header(conn, "idempotency-key")
        assert idempotency_key =~ ~r/^[0-9a-f]{64}$/

        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert JSON.decode!(body) == %{
                 "data" => %{
                   "type" => "playlists",
                   "attributes" => %{
                     "name" => "Test Playlist",
                     "description" => "Test Description",
                     "accessType" => "UNLISTED"
                   }
                 }
               }

        json_api_resp(conn, 201, %{
          "data" => %{"id" => "5a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9", "type" => "playlists"}
        })
      end)

      assert {:ok, playlist} =
               ExternalClient.create_playlist(user_session, "Test Playlist", "Test Description")

      assert playlist.id == "5a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9"
      assert playlist.external_url == "https://tidal.com/playlist/5a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9"
    end

    test "sends the same idempotency key for identical create requests", %{user_session: user_session} do
      test_pid = self()

      Req.Test.expect(MyTidalStub, 2, fn conn ->
        [key] = Plug.Conn.get_req_header(conn, "idempotency-key")
        send(test_pid, {:idempotency_key, key})

        json_api_resp(conn, 201, %{"data" => %{"id" => "same-playlist", "type" => "playlists"}})
      end)

      {:ok, _} = ExternalClient.create_playlist(user_session, "Name", "Description")
      {:ok, _} = ExternalClient.create_playlist(user_session, "Name", "Description")

      assert_receive {:idempotency_key, first_key}
      assert_receive {:idempotency_key, second_key}
      assert first_key == second_key
    end

    @tag :capture_log
    test "returns an error on an unexpected status", %{user_session: user_session} do
      Req.Test.expect(MyTidalStub, fn conn ->
        json_api_resp(conn, 400, %{
          "errors" => [%{"code" => "INVALID_REQUEST_BODY", "detail" => "bad"}]
        })
      end)

      assert {:error, :playlist_creation_failed} =
               ExternalClient.create_playlist(user_session, "Test Playlist", "Test Description")
    end

    @tag :capture_log
    test "surfaces a 429 as {:error, {:rate_limited, retry_after}}", %{user_session: user_session} do
      Req.Test.expect(MyTidalStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "4")
        |> Plug.Conn.send_resp(429, "")
      end)

      assert {:error, {:rate_limited, 4}} =
               ExternalClient.create_playlist(user_session, "Test Playlist", "Test Description")
    end
  end

  describe "add_tracks_to_playlist/3" do
    test "adds tracks in chunks of 20 with per-chunk idempotency keys", %{user_session: user_session} do
      test_pid = self()
      tracks = Enum.map(1..45, &"track-#{&1}")

      Req.Test.expect(MyTidalStub, 3, fn %{method: "POST"} = conn ->
        assert conn.request_path == "/v2/playlists/playlist123/relationships/items"

        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["countryCode"] == @country_code

        [idempotency_key] = Plug.Conn.get_req_header(conn, "idempotency-key")

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"data" => data} = JSON.decode!(body)

        assert Enum.all?(data, &(&1["type"] == "tracks"))
        refute Map.has_key?(JSON.decode!(body), "meta")

        send(test_pid, {:chunk, Enum.map(data, & &1["id"]), idempotency_key})

        Plug.Conn.send_resp(conn, 201, "")
      end)

      assert {:ok, :tracks_added} =
               ExternalClient.add_tracks_to_playlist(user_session, "playlist123", tracks)

      assert_receive {:chunk, first_chunk, first_key}
      assert_receive {:chunk, second_chunk, second_key}
      assert_receive {:chunk, third_chunk, third_key}

      assert first_chunk == Enum.map(1..20, &"track-#{&1}")
      assert second_chunk == Enum.map(21..40, &"track-#{&1}")
      assert third_chunk == Enum.map(41..45, &"track-#{&1}")

      assert [first_key, second_key, third_key] |> Enum.uniq() |> length() == 3
    end

    @tag :capture_log
    test "halts on the first failing chunk", %{user_session: user_session} do
      tracks = Enum.map(1..25, &"track-#{&1}")

      Req.Test.expect(MyTidalStub, fn conn -> Plug.Conn.send_resp(conn, 201, "") end)
      Req.Test.expect(MyTidalStub, fn conn -> Plug.Conn.send_resp(conn, 500, "") end)

      assert {:error, :tracks_addition_failed} =
               ExternalClient.add_tracks_to_playlist(user_session, "playlist123", tracks)
    end

    @tag :capture_log
    test "surfaces a mid-chunk 429 as {:error, {:rate_limited, retry_after}}",
         %{user_session: user_session} do
      tracks = Enum.map(1..25, &"track-#{&1}")

      Req.Test.expect(MyTidalStub, fn conn -> Plug.Conn.send_resp(conn, 201, "") end)

      Req.Test.expect(MyTidalStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "4")
        |> Plug.Conn.send_resp(429, "")
      end)

      assert {:error, {:rate_limited, 4}} =
               ExternalClient.add_tracks_to_playlist(user_session, "playlist123", tracks)
    end

    test "handles empty track list gracefully", %{user_session: user_session} do
      assert {:ok, :no_tracks} =
               ExternalClient.add_tracks_to_playlist(user_session, "playlist123", [])
    end
  end

  describe "refresh_token/1" do
    test "returns the new access token without a refresh token (Tidal does not rotate)" do
      Req.Test.expect(MyTidalStub, fn conn ->
        assert conn.request_path == "/v1/oauth2/token"

        assert "application/x-www-form-urlencoded" in Plug.Conn.get_req_header(conn, "content-type")

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        assert params["grant_type"] == "refresh_token"
        assert params["refresh_token"] == "old_refresh_token"
        assert params["client_id"]
        assert params["client_secret"]

        # Tidal's refresh response has NO refresh_token field.
        Req.Test.json(conn, %{
          "access_token" => "new_access_token",
          "expires_in" => 14_400,
          "token_type" => "Bearer",
          "scope" => "user.read playlists.write",
          "user_id" => 12_345
        })
      end)

      assert {:ok, tokens} = ExternalClient.refresh_token("old_refresh_token")
      assert tokens == %{access_token: "new_access_token", expires_in: 14_400}
    end

    @tag :capture_log
    test "returns error on invalid token" do
      Req.Test.expect(MyTidalStub, fn conn -> Plug.Conn.send_resp(conn, 401, "Unauthorized") end)

      assert {:error, :invalid_token} = ExternalClient.refresh_token("invalid_token")
    end

    @tag :capture_log
    test "returns error on server error" do
      Req.Test.expect(MyTidalStub, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      assert {:error, :refresh_failed} = ExternalClient.refresh_token("some_token")
    end
  end

  describe "refresh_to_user_session/1" do
    test "builds the session from the JWT claims, preserving the refresh token" do
      access_token = jwt(%{"uid" => 12_345, "cc" => "US"})

      Req.Test.expect(MyTidalStub, fn conn ->
        Req.Test.json(conn, %{"access_token" => access_token, "expires_in" => 14_400})
      end)

      assert {:ok, %UserSession{} = user_session} =
               ExternalClient.refresh_to_user_session("stored_refresh_token")

      assert user_session.access_token == access_token
      assert user_session.refresh_token == "stored_refresh_token"
      assert user_session.user_id == "12345"
      assert user_session.country_code == "US"
      assert user_session.expires_at > System.system_time(:second)
    end

    @tag :capture_log
    test "returns error when token refresh fails" do
      Req.Test.expect(MyTidalStub, fn conn ->
        Plug.Conn.send_resp(conn, 401, "Unauthorized")
      end)

      assert {:error, :invalid_token} = ExternalClient.refresh_to_user_session("bad_token")
    end
  end

  describe "exchange_code/3" do
    test "exchanges the code with the PKCE verifier and builds the session from JWT claims" do
      access_token = jwt(%{"uid" => 12_345, "cc" => "NO"})

      Req.Test.expect(MyTidalStub, fn conn ->
        assert conn.request_path == "/v1/oauth2/token"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        assert params["grant_type"] == "authorization_code"
        assert params["code"] == "valid_code"
        assert params["redirect_uri"] == "http://127.0.0.1:4000/oauth/callbacks/tidal"
        assert params["code_verifier"] == "pkce_verifier"
        assert params["client_id"]
        assert params["client_secret"]

        Req.Test.json(conn, %{
          "access_token" => access_token,
          "refresh_token" => "new_refresh_token",
          "expires_in" => 14_400,
          "token_type" => "Bearer",
          "scope" => "user.read playlists.write",
          "user_id" => 12_345
        })
      end)

      assert {:ok, %UserSession{} = user_session} =
               ExternalClient.exchange_code(
                 "valid_code",
                 "http://127.0.0.1:4000/oauth/callbacks/tidal",
                 "pkce_verifier"
               )

      assert user_session.access_token == access_token
      assert user_session.refresh_token == "new_refresh_token"
      assert user_session.user_id == "12345"
      assert user_session.country_code == "NO"
      assert user_session.expires_at > System.system_time(:second)
    end

    @tag :capture_log
    test "blows up loudly when the JWT is missing the cc claim" do
      # Deliberate (ADR-004 §1): a missing claim must fail sign-in, not
      # silently build a broken session.
      access_token = jwt(%{"uid" => 12_345})

      Req.Test.expect(MyTidalStub, fn conn ->
        Req.Test.json(conn, %{
          "access_token" => access_token,
          "refresh_token" => "new_refresh_token",
          "expires_in" => 14_400
        })
      end)

      assert_raise KeyError, fn ->
        ExternalClient.exchange_code("valid_code", "http://127.0.0.1:4000/oauth/callbacks/tidal", "v")
      end
    end

    @tag :capture_log
    test "returns error with invalid code" do
      Req.Test.expect(MyTidalStub, fn conn ->
        Req.Test.json(%{conn | status: 400}, %{
          "error" => "invalid_grant",
          "error_description" => "Authorization code expired"
        })
      end)

      assert {:error, :invalid_code} =
               ExternalClient.exchange_code("expired_code", "http://127.0.0.1:4000/oauth/callbacks/tidal", "v")
    end

    @tag :capture_log
    test "returns error on unexpected status" do
      Req.Test.expect(MyTidalStub, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      assert {:error, {:unexpected_status, 500, _}} =
               ExternalClient.exchange_code("valid_code", "http://127.0.0.1:4000/oauth/callbacks/tidal", "v")
    end
  end

  describe "with expired token" do
    setup %{user_session: user_session} do
      SessionSupervisor.stop_user_token(@user_id)

      {:ok, pid} =
        SessionSupervisor.start_user_token(@user_id, %{user_session | access_token: "expired_access_token"})

      on_exit(fn -> SessionSupervisor.stop_user_token(@user_id) end)

      {:ok, session_pid: pid}
    end

    test "handles 401 responses by refreshing the token and retrying once",
         %{user_session: user_session, session_pid: pid} do
      expect(MockClient, :refresh_token, fn "refresh_token" ->
        {:ok, %{access_token: "fresh_access_token", expires_in: 14_400}}
      end)

      # Refreshing happens in the SessionManager process, so it must be
      # explicitly allowed to use this test's mock expectations.
      allow(MockClient, self(), pid)

      Req.Test.expect(MyTidalStub, fn conn ->
        Plug.Conn.send_resp(conn, 401, "")
      end)

      Req.Test.expect(MyTidalStub, fn conn ->
        assert ["Bearer fresh_access_token"] = Plug.Conn.get_req_header(conn, "authorization")

        json_api_resp(
          conn,
          200,
          search_response([
            %{id: "251380837", title: "Dramamine", artists: [%{id: "9x1", name: "Modest Mouse"}]}
          ])
        )
      end)

      assert %{track_id: "251380837"} =
               ExternalClient.search_for_track(user_session, "Modest Mouse", "Dramamine")
    end

    @tag :capture_log
    test "returns error when the token refresh fails",
         %{user_session: user_session, session_pid: pid} do
      expect(MockClient, :refresh_token, fn _refresh_token ->
        {:error, :invalid_token}
      end)

      allow(MockClient, self(), pid)

      Req.Test.expect(MyTidalStub, fn conn ->
        Plug.Conn.send_resp(conn, 401, "")
      end)

      assert {:error, :token_refresh_failed} =
               ExternalClient.create_playlist(user_session, "Test Playlist", "Test Description")
    end
  end
end
