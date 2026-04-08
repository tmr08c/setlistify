defmodule Setlistify.AppleMusic.APITest do
  use Setlistify.DataCase, async: false

  import Hammox

  alias Setlistify.AppleMusic.API
  alias Setlistify.AppleMusic.UserSession

  # Cache fetching happens in another process, managed by Cachex. The process we
  # start in our application tree is a supervisor, so explicitly `allow`ing with
  # that PID does not work. This will enable "global" mode which means any
  # process will respect our `expect` at the cost of not being able to run with
  # `async: true`
  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    on_exit(:clear_cache, fn ->
      Cachex.clear!(:apple_music_track_cache)
    end)

    user_session = %UserSession{user_token: "token", storefront: "us", user_id: "user-123"}

    {:ok, user_session: user_session}
  end

  describe "build_user_session/3" do
    test "returns a UserSession struct with the given fields" do
      assert {:ok, %UserSession{} = session} =
               API.build_user_session("user_token", "us", "user-id-123")

      assert session.user_token == "user_token"
      assert session.storefront == "us"
      assert session.user_id == "user-id-123"
    end
  end

  describe "search_for_track/3" do
    test "returns the full error tuple when impl returns an error", %{
      user_session: user_session
    } do
      expect(Setlistify.AppleMusic.API.MockClient, :search_for_track, 1, fn _session,
                                                                            _artist,
                                                                            _track ->
        {:error, :token_refresh_failed}
      end)

      assert {:error, :token_refresh_failed} =
               API.search_for_track(user_session, "Artist", "Track")
    end

    test "caches successful results — impl is called only once", %{user_session: user_session} do
      expect(Setlistify.AppleMusic.API.MockClient, :search_for_track, 1, fn _session,
                                                                            _artist,
                                                                            _track ->
        %{track_id: "am:track:abc123"}
      end)

      assert %{track_id: "am:track:abc123"} =
               API.search_for_track(user_session, "Artist", "Track")

      assert %{track_id: "am:track:abc123"} =
               API.search_for_track(user_session, "Artist", "Track")
    end
  end
end
