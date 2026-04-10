defmodule Setlistify.UserSessionManagerTest do
  use ExUnit.Case, async: true

  import Setlistify.Test.RegistryHelpers

  alias Setlistify.AppleMusic.UserSession, as: AppleMusicSession
  alias Setlistify.Spotify.UserSession, as: SpotifySession
  alias Setlistify.UserSessionManager

  setup do
    user_id = unique_user_id()

    spotify_session = %SpotifySession{
      access_token: "access",
      refresh_token: "refresh",
      expires_at: System.system_time(:second) + 3600,
      user_id: user_id,
      username: "testuser"
    }

    apple_music_session = %AppleMusicSession{
      user_token: "user_token",
      user_id: user_id,
      storefront: "us"
    }

    {:ok,
     %{
       user_id: user_id,
       spotify_session: spotify_session,
       apple_music_session: apple_music_session
     }}
  end

  describe "start/1" do
    test "routes Spotify session to Spotify.SessionManager", %{
      user_id: user_id,
      spotify_session: session
    } do
      assert {:ok, _pid} = UserSessionManager.start(session)
      assert_in_registry({:spotify, user_id})
    end

    test "routes AppleMusic session to AppleMusic.SessionManager", %{
      user_id: user_id,
      apple_music_session: session
    } do
      assert {:ok, _pid} = UserSessionManager.start(session)
      assert_in_registry({:apple_music, user_id})
    end

    test "registers each provider under its own namespace", %{
      user_id: user_id,
      spotify_session: spotify_session,
      apple_music_session: apple_music_session
    } do
      UserSessionManager.start(spotify_session)
      assert {:ok, _} = UserSessionManager.get_session({:spotify, user_id})
      assert {:error, :not_found} = UserSessionManager.get_session({:apple_music, user_id})

      UserSessionManager.start(apple_music_session)
      assert {:ok, _} = UserSessionManager.get_session({:apple_music, user_id})
    end
  end

  describe "get_session/1" do
    test "returns the session for the correct provider", %{
      user_id: user_id,
      spotify_session: spotify_session,
      apple_music_session: apple_music_session
    } do
      UserSessionManager.start(spotify_session)
      UserSessionManager.start(apple_music_session)

      assert {:ok, ^spotify_session} = UserSessionManager.get_session({:spotify, user_id})
      assert {:ok, ^apple_music_session} = UserSessionManager.get_session({:apple_music, user_id})
    end

    test "returns :not_found when no session exists" do
      assert {:error, :not_found} =
               UserSessionManager.get_session({:spotify, unique_user_id()})

      assert {:error, :not_found} =
               UserSessionManager.get_session({:apple_music, unique_user_id()})
    end
  end

  describe "stop/1" do
    test "terminates the session process", %{
      user_id: user_id,
      spotify_session: spotify_session,
      apple_music_session: apple_music_session
    } do
      for {key, session} <- [{:spotify, spotify_session}, {:apple_music, apple_music_session}] do
        {:ok, pid} = UserSessionManager.start(session)
        assert Process.alive?(pid)
        assert :ok = UserSessionManager.stop({key, user_id})
        refute Process.alive?(pid)
      end
    end

    test "returns :not_found when no session exists" do
      assert {:error, :not_found} = UserSessionManager.stop({:spotify, unique_user_id()})
      assert {:error, :not_found} = UserSessionManager.stop({:apple_music, unique_user_id()})
    end
  end
end
