defmodule Setlistify.Tidal.APITest do
  use ExUnit.Case, async: true

  import Hammox

  alias Setlistify.Tidal.API
  alias Setlistify.Tidal.API.MockClient
  alias Setlistify.Tidal.UserSession

  setup :verify_on_exit!

  setup do
    user_session = %UserSession{
      access_token: "token",
      refresh_token: "refresh_token",
      expires_at: System.system_time(:second) + 14_400,
      user_id: "12345",
      country_code: "US"
    }

    {:ok, user_session: user_session}
  end

  describe "search_for_track/4" do
    # The application registers :tidal_track_cache in #141; until then (and for
    # async isolation) each test run starts it here.
    setup do
      start_supervised!({Cachex, name: :tidal_track_cache})
      :ok
    end

    test "delegates to the impl through the cache", %{user_session: user_session} do
      expect(MockClient, :search_for_track, 1, fn _session, "Modest Mouse", "Dramamine", nil ->
        %{track_id: "251380837"}
      end)

      assert %{track_id: "251380837"} =
               API.search_for_track(user_session, "Modest Mouse", "Dramamine")
    end

    test "caches results so repeat searches skip the impl", %{user_session: user_session} do
      expect(MockClient, :search_for_track, 1, fn _session, _artist, _track, _cover ->
        %{track_id: "251380837"}
      end)

      assert %{track_id: "251380837"} =
               API.search_for_track(user_session, "Modest Mouse", "Dramamine", "Cursive")

      # Second identical call must be served from the cache (the mock above
      # only allows a single invocation).
      assert %{track_id: "251380837"} =
               API.search_for_track(user_session, "Modest Mouse", "Dramamine", "Cursive")
    end

    test "does not cache errors", %{user_session: user_session} do
      expect(MockClient, :search_for_track, 2, fn _session, _artist, _track, _cover ->
        {:error, {:rate_limited, 4}}
      end)

      assert {:error, {:rate_limited, 4}} = API.search_for_track(user_session, "a", "t")
      assert {:error, {:rate_limited, 4}} = API.search_for_track(user_session, "a", "t")
    end
  end

  describe "create_playlist/3" do
    test "delegates to the impl", %{user_session: user_session} do
      expect(MockClient, :create_playlist, 1, fn _session, "Name", "Description" ->
        {:ok, %{id: "playlist-id", external_url: "https://tidal.com/playlist/playlist-id"}}
      end)

      assert {:ok, %{id: "playlist-id"}} = API.create_playlist(user_session, "Name", "Description")
    end
  end

  describe "add_tracks_to_playlist/3" do
    test "delegates to the impl", %{user_session: user_session} do
      expect(MockClient, :add_tracks_to_playlist, 1, fn _session, "playlist-id", ["track-1"] ->
        {:ok, :tracks_added}
      end)

      assert {:ok, :tracks_added} = API.add_tracks_to_playlist(user_session, "playlist-id", ["track-1"])
    end
  end

  describe "exchange_code/3" do
    test "delegates to the impl and returns the session", %{user_session: user_session} do
      expect(MockClient, :exchange_code, 1, fn "code", "https://127.0.0.1/cb", "verifier" ->
        {:ok, user_session}
      end)

      assert {:ok, ^user_session} = API.exchange_code("code", "https://127.0.0.1/cb", "verifier")
    end
  end

  describe "refresh_token/1" do
    test "delegates to the impl and returns the result" do
      expect(MockClient, :refresh_token, 1, fn "refresh-abc" ->
        {:ok, %{access_token: "new-access", expires_in: 14_400}}
      end)

      assert {:ok, %{access_token: "new-access", expires_in: 14_400}} =
               API.refresh_token("refresh-abc")
    end

    test "returns the error when impl returns an error" do
      expect(MockClient, :refresh_token, 1, fn _refresh_token ->
        {:error, :invalid_token}
      end)

      assert {:error, :invalid_token} = API.refresh_token("bad-token")
    end
  end

  describe "refresh_to_user_session/1" do
    test "delegates to the impl and returns the session", %{user_session: user_session} do
      expect(MockClient, :refresh_to_user_session, 1, fn "refresh-abc" ->
        {:ok, user_session}
      end)

      assert {:ok, ^user_session} = API.refresh_to_user_session("refresh-abc")
    end
  end
end
