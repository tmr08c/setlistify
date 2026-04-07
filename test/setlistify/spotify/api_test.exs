defmodule Setlistify.Spotify.APITest do
  use Setlistify.DataCase, async: false

  import Hammox

  alias Setlistify.Spotify.API
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

  describe "search_for_track/3" do
    test "returns the full error tuple when impl returns an error", %{
      user_session: user_session
    } do
      expect(Setlistify.Spotify.API.MockClient, :search_for_track, 1, fn _session,
                                                                         _artist,
                                                                         _track ->
        {:error, :token_refresh_failed}
      end)

      # Without the fix, elem(1) on Cachex's {:error, :token_refresh_failed} return
      # yields just :token_refresh_failed (the atom), not the full error tuple
      assert {:error, :token_refresh_failed} =
               API.search_for_track(user_session, "Artist", "Track")
    end

    test "caches successful results — impl is called only once", %{user_session: user_session} do
      expect(Setlistify.Spotify.API.MockClient, :search_for_track, 1, fn _session,
                                                                         _artist,
                                                                         _track ->
        %{track_id: "spotify:track:abc123"}
      end)

      assert %{track_id: "spotify:track:abc123"} =
               API.search_for_track(user_session, "Artist", "Track")

      assert %{track_id: "spotify:track:abc123"} =
               API.search_for_track(user_session, "Artist", "Track")
    end
  end
end
