defmodule Setlistify.Spotify.UserSessionTest do
  use ExUnit.Case, async: true

  alias Setlistify.Spotify.UserSession

  test "creates a valid user session with required fields" do
    session = %UserSession{
      access_token: "test_access_token",
      refresh_token: "test_refresh_token",
      expires_at: 1_234_567_890,
      user_id: "spotify_user_123",
      username: "testuser"
    }

    assert session.access_token == "test_access_token"
    assert session.refresh_token == "test_refresh_token"
    assert session.expires_at == 1_234_567_890
    assert session.user_id == "spotify_user_123"
    assert session.username == "testuser"
  end

  test "enforces required keys" do
    # Create a complete session map
    complete_session_map = %{
      access_token: "test_access_token",
      refresh_token: "test_refresh_token",
      expires_at: 1_234_567_890,
      user_id: "spotify_user_123",
      username: "testuser"
    }

    # Test that each key is required by removing it and trying to create the struct
    for key <- Map.keys(complete_session_map) do
      session_with_missing_key = Map.delete(complete_session_map, key)

      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(UserSession, session_with_missing_key)
      end
    end
  end
end
