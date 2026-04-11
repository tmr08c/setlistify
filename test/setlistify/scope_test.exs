defmodule Setlistify.ScopeTest do
  use ExUnit.Case, async: true

  alias Setlistify.AppleMusic
  alias Setlistify.Scope
  alias Setlistify.Spotify

  describe "for_user_session/1" do
    test "returns a blank scope for nil" do
      scope = Scope.for_user_session(nil)

      assert scope.user_id == nil
      assert scope.user_session == nil
    end

    test "builds a scope from a Spotify user session" do
      user_session = %Spotify.UserSession{
        user_id: "spotify-user-1",
        username: "Test User",
        access_token: "access",
        refresh_token: "refresh",
        expires_at: System.system_time(:second) + 3600
      }

      scope = Scope.for_user_session(user_session)

      assert scope.user_id == "spotify-user-1"
      assert scope.user_session == user_session
    end

    test "builds a scope from an Apple Music user session" do
      user_session = %AppleMusic.UserSession{
        user_id: "apple-user-1",
        user_token: "token",
        storefront: "us"
      }

      scope = Scope.for_user_session(user_session)

      assert scope.user_id == "apple-user-1"
      assert scope.user_session == user_session
    end
  end

  describe "authenticated?/1" do
    test "returns false for a blank scope" do
      refute Scope.authenticated?(Scope.for_user_session(nil))
    end

    test "returns true when a user session is present" do
      user_session = %Spotify.UserSession{
        user_id: "u1",
        username: "User",
        access_token: "tok",
        refresh_token: "ref",
        expires_at: System.system_time(:second) + 3600
      }

      assert Scope.authenticated?(Scope.for_user_session(user_session))
    end
  end
end
