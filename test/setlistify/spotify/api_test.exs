defmodule Setlistify.Spotify.APITest do
  use Setlistify.DataCase, async: false

  import Hammox

  alias Setlistify.Spotify.API
  alias Setlistify.Spotify.API.MockClient
  alias Setlistify.Spotify.UserSession

  # Cachex runs in a separate process, so we need global mox mode
  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    on_exit(:clear_cache, fn ->
      Cachex.clear!(:spotify_track_cache)
    end)

    user_session = %UserSession{
      access_token: "token",
      refresh_token: "refresh_token",
      expires_at: System.system_time(:second) + 3600,
      user_id: "user-123",
      username: "Test User"
    }

    {:ok, user_session: user_session}
  end

  describe "create_playlist/3" do
    test "delegates to the impl and returns the result", %{user_session: user_session} do
      expect(Setlistify.Spotify.API.MockClient, :create_playlist, 1, fn _session,
                                                                        _name,
                                                                        _description ->
        {:ok, %{id: "playlist-1", external_url: "https://open.spotify.com/playlist/1"}}
      end)

      assert {:ok, %{id: "playlist-1", external_url: "https://open.spotify.com/playlist/1"}} =
               API.create_playlist(user_session, "My Setlist", "Songs from a concert")
    end

    test "returns the error when impl returns an error", %{user_session: user_session} do
      expect(Setlistify.Spotify.API.MockClient, :create_playlist, 1, fn _session,
                                                                        _name,
                                                                        _description ->
        {:error, :unauthorized}
      end)

      assert {:error, :unauthorized} =
               API.create_playlist(user_session, "My Setlist", "Songs from a concert")
    end
  end

  describe "add_tracks_to_playlist/3" do
    test "delegates to the impl and returns the result", %{user_session: user_session} do
      expect(Setlistify.Spotify.API.MockClient, :add_tracks_to_playlist, 1, fn _session,
                                                                               _playlist_id,
                                                                               _tracks ->
        {:ok, :tracks_added}
      end)

      assert {:ok, :tracks_added} =
               API.add_tracks_to_playlist(user_session, "playlist-1", [
                 "spotify:track:abc",
                 "spotify:track:def"
               ])
    end

    test "returns the error when impl returns an error", %{user_session: user_session} do
      expect(Setlistify.Spotify.API.MockClient, :add_tracks_to_playlist, 1, fn _session,
                                                                               _playlist_id,
                                                                               _tracks ->
        {:error, :rate_limited}
      end)

      assert {:error, :rate_limited} =
               API.add_tracks_to_playlist(user_session, "playlist-1", [
                 "spotify:track:abc"
               ])
    end
  end

  describe "search_for_track/3" do
    test "returns the full error tuple when impl returns an error", %{
      user_session: user_session
    } do
      expect(MockClient, :search_for_track, 1, fn _session, _artist, _track ->
        {:error, :token_refresh_failed}
      end)

      assert {:error, :token_refresh_failed} =
               API.search_for_track(user_session, "Artist", "Track")
    end

    test "caches successful results — impl is called only once", %{user_session: user_session} do
      expect(MockClient, :search_for_track, 1, fn _session, _artist, _track ->
        %{track_id: "spotify:track:abc123"}
      end)

      assert %{track_id: "spotify:track:abc123"} =
               API.search_for_track(user_session, "Artist", "Track")

      assert %{track_id: "spotify:track:abc123"} =
               API.search_for_track(user_session, "Artist", "Track")
    end
  end
end
