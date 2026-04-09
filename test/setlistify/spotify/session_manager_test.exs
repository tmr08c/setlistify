defmodule Setlistify.Spotify.SessionManagerTest do
  use ExUnit.Case, async: true

  import Hammox
  import Setlistify.Test.RegistryHelpers

  alias Setlistify.Spotify.SessionManager
  alias Setlistify.Spotify.UserSession

  @refresh_token "test_refresh_token"

  setup :verify_on_exit!

  setup do
    # Generate a unique user_id for each test
    user_id = unique_user_id()

    # Create tokens structure with the user's refresh token
    initial_token = %{
      access_token: "initial_access_token",
      refresh_token: @refresh_token,
      expires_in: 3600
    }

    {:ok, %{user_id: user_id, initial_token: initial_token}}
  end

  describe "start_link/1" do
    test "starts a new session manager process", %{user_id: user_id, initial_token: initial_token} do
      user_session = %UserSession{
        access_token: initial_token.access_token,
        refresh_token: initial_token.refresh_token,
        expires_at: System.system_time(:second) + initial_token.expires_in,
        user_id: user_id,
        username: "test_user"
      }

      assert {:ok, pid} = SessionManager.start_link({user_id, user_session})
      assert Process.alive?(pid)
    end

    test "registers process with Registry", %{user_id: user_id, initial_token: initial_token} do
      user_session = %UserSession{
        access_token: initial_token.access_token,
        refresh_token: initial_token.refresh_token,
        expires_at: System.system_time(:second) + initial_token.expires_in,
        user_id: user_id,
        username: "test_user"
      }

      {:ok, pid} = SessionManager.start_link({user_id, user_session})
      registry_pid = assert_in_registry({:spotify, user_id})
      assert registry_pid == pid
    end

    test "handles UserSession struct", %{user_id: user_id} do
      user_session = %UserSession{
        access_token: "test_access_token",
        refresh_token: @refresh_token,
        expires_at: System.system_time(:second) + 3600,
        user_id: user_id,
        username: "test_user"
      }

      assert {:ok, pid} = SessionManager.start_link({user_id, user_session})
      assert Process.alive?(pid)
      assert {:ok, "test_access_token"} = SessionManager.get_token(user_id)
    end
  end

  describe "get_token/1" do
    test "returns current access token", %{user_id: user_id, initial_token: initial_token} do
      user_session = %UserSession{
        access_token: initial_token.access_token,
        refresh_token: initial_token.refresh_token,
        expires_at: System.system_time(:second) + initial_token.expires_in,
        user_id: user_id,
        username: "test_user"
      }

      {:ok, _pid} = SessionManager.start_link({user_id, user_session})
      assert {:ok, "initial_access_token"} = SessionManager.get_token(user_id)
    end

    test "returns error when process not found", %{user_id: _user_id} do
      nonexistent_user = unique_user_id()
      assert {:error, :not_found} = SessionManager.get_token(nonexistent_user)
    end
  end

  describe "get_session/1" do
    test "returns UserSession struct", %{user_id: user_id, initial_token: initial_token} do
      user_session = %UserSession{
        access_token: initial_token.access_token,
        refresh_token: initial_token.refresh_token,
        expires_at: System.system_time(:second) + initial_token.expires_in,
        user_id: user_id,
        username: "test_user"
      }

      {:ok, _pid} = SessionManager.start_link({user_id, user_session})
      assert {:ok, session} = SessionManager.get_session(user_id)
      assert %UserSession{} = session
      assert session.access_token == "initial_access_token"
      assert session.refresh_token == @refresh_token
      assert session.user_id == user_id
    end

    test "returns UserSession struct when initialized with UserSession", %{user_id: user_id} do
      user_session = %UserSession{
        access_token: "test_access_token",
        refresh_token: @refresh_token,
        expires_at: System.system_time(:second) + 3600,
        user_id: user_id,
        username: "test_user"
      }

      {:ok, _pid} = SessionManager.start_link({user_id, user_session})
      assert {:ok, returned_session} = SessionManager.get_session(user_id)
      assert %UserSession{} = returned_session
      assert returned_session.access_token == "test_access_token"
      assert returned_session.username == "test_user"
    end

    test "returns error when process not found", %{user_id: _user_id} do
      nonexistent_user = unique_user_id()
      assert {:error, :not_found} = SessionManager.get_session(nonexistent_user)
    end
  end

  describe "stop/1" do
    test "terminates the process", %{user_id: user_id, initial_token: initial_token} do
      user_session = %UserSession{
        access_token: initial_token.access_token,
        refresh_token: initial_token.refresh_token,
        expires_at: System.system_time(:second) + initial_token.expires_in,
        user_id: user_id,
        username: "test_user"
      }

      {:ok, pid} = SessionManager.start_link({user_id, user_session})
      assert Process.alive?(pid)
      assert :ok = SessionManager.stop(user_id)
      refute Process.alive?(pid)
    end

    test "returns :not_found when no process exists", %{user_id: _user_id} do
      nonexistent_user = unique_user_id()
      assert {:error, :not_found} = SessionManager.stop(nonexistent_user)
    end
  end

  describe "lookup/1" do
    test "returns {:ok, pid} when process is registered", %{
      user_id: user_id,
      initial_token: initial_token
    } do
      user_session = %UserSession{
        access_token: initial_token.access_token,
        refresh_token: initial_token.refresh_token,
        expires_at: System.system_time(:second) + initial_token.expires_in,
        user_id: user_id,
        username: "test_user"
      }

      {:ok, pid} = SessionManager.start_link({user_id, user_session})
      assert {:ok, ^pid} = SessionManager.lookup(user_id)
    end

    test "returns :error when no process is registered", %{user_id: _user_id} do
      nonexistent_user = unique_user_id()
      assert :error = SessionManager.lookup(nonexistent_user)
    end
  end

  describe "refresh_session/1" do
    test "refreshes token and returns UserSession", %{
      user_id: user_id,
      initial_token: initial_token
    } do
      user_session = %UserSession{
        access_token: initial_token.access_token,
        refresh_token: initial_token.refresh_token,
        expires_at: System.system_time(:second) + initial_token.expires_in,
        user_id: user_id,
        username: "test_user"
      }

      {:ok, pid} = SessionManager.start_link({user_id, user_session})

      expect(Setlistify.Spotify.API.MockClient, :refresh_token, fn refresh_token ->
        assert refresh_token == initial_token.refresh_token

        {:ok,
         %{
           access_token: "new_access_token",
           refresh_token: @refresh_token,
           expires_in: 3600
         }}
      end)

      allow(Setlistify.Spotify.API.MockClient, self(), pid)

      assert {:ok, session} = SessionManager.refresh_session(user_id)
      assert %UserSession{} = session
      assert session.access_token == "new_access_token"
      assert session.refresh_token == @refresh_token
      assert session.user_id == user_id
      assert session.expires_at > System.system_time(:second)
    end

    @tag :capture_log
    test "terminates process on refresh failure", %{
      user_id: user_id,
      initial_token: initial_token
    } do
      user_session = %UserSession{
        access_token: initial_token.access_token,
        refresh_token: initial_token.refresh_token,
        expires_at: System.system_time(:second) + initial_token.expires_in,
        user_id: user_id,
        username: "test_user"
      }

      {:ok, pid} = SessionManager.start_link({user_id, user_session})

      expect(Setlistify.Spotify.API.MockClient, :refresh_token, fn refresh_token ->
        assert refresh_token == initial_token.refresh_token
        {:error, :invalid_token}
      end)

      allow(Setlistify.Spotify.API.MockClient, self(), pid)

      assert {:error, :invalid_token} = SessionManager.refresh_session(user_id)
      refute Process.alive?(pid)
    end

    test "returns error when process not found", %{user_id: _user_id} do
      nonexistent_user = unique_user_id()
      assert {:error, :not_found} = SessionManager.refresh_session(nonexistent_user)
    end
  end

  describe "automatic refresh" do
    # This test is prone to race conditions and async issues since it relies on timers and process messaging
    # We'll skip it for now as it's not related to the main refactoring work
    test "schedules token refresh before expiration", %{
      user_id: user_id,
      initial_token: initial_token
    } do
      expect(Setlistify.Spotify.API.MockClient, :refresh_token, fn refresh_token ->
        assert initial_token.access_token != "refreshed_token"
        assert refresh_token == initial_token.refresh_token

        {:ok,
         %{
           access_token: "refreshed_token",
           refresh_token: refresh_token,
           expires_in: 3600
         }}
      end)

      # Allow refresh_token message using global mode
      # Allow the mock to be called from the session process
      allow(Setlistify.Spotify.API.MockClient, self(), fn ->
        # Wait for the process to be registered and return it
        # This avoids flakiness issues where the Registry lookup might happen
        # before the process is registered
        # In this test, we're starting the process after setting up the mock,
        # so we don't want to fail if the process isn't registered yet
        pid = assert_in_registry({:spotify, user_id}, fail_on_timeout: false)
        if is_nil(pid), do: self(), else: pid
      end)

      # Set `expires_in` to short duration, something quicker than
      # @refresh_threshold, so we will attempt to refresh right away.
      token = %{initial_token | expires_in: 1}

      # Create a UserSession for the test
      user_session = %UserSession{
        access_token: token.access_token,
        refresh_token: token.refresh_token,
        expires_at: System.system_time(:second) + token.expires_in,
        user_id: user_id,
        username: "test_user"
      }

      # Start the session process which should trigger a refresh immediately
      {:ok, pid} = SessionManager.start_link({user_id, user_session})

      assert Process.alive?(pid)

      # Verify the token was refreshed
      assert {:ok, "refreshed_token"} = SessionManager.get_token(user_id)
    end
  end

  describe "PubSub broadcasting" do
    test "broadcasts token refresh to the user's channel", %{
      user_id: user_id,
      initial_token: initial_token
    } do
      # Subscribe to the user's channel
      Phoenix.PubSub.subscribe(Setlistify.PubSub, "user:#{user_id}")

      # Mock the refresh_token API call
      expect(Setlistify.Spotify.API.MockClient, :refresh_token, fn _refresh_token ->
        {:ok,
         %{
           access_token: "new_access_token",
           refresh_token: @refresh_token,
           expires_in: 3600
         }}
      end)

      # Start the session
      user_session = %UserSession{
        access_token: initial_token.access_token,
        refresh_token: initial_token.refresh_token,
        expires_at: System.system_time(:second) + initial_token.expires_in,
        user_id: user_id,
        username: "test_user"
      }

      {:ok, pid} = SessionManager.start_link({user_id, user_session})

      # Ensure we're allowing the right process
      allow(Setlistify.Spotify.API.MockClient, self(), pid)

      # Trigger a refresh
      assert {:ok, session} = SessionManager.refresh_session(user_id)
      assert session.access_token == "new_access_token"

      # Should receive the broadcast
      assert_receive {:token_refreshed,
                      %UserSession{
                        access_token: "new_access_token",
                        refresh_token: @refresh_token,
                        user_id: ^user_id
                      }}
    end

    test "does not broadcast to other users' channels", %{initial_token: initial_token} do
      user1_id = unique_user_id()
      user2_id = unique_user_id()

      # Subscribe to user2's channel
      Phoenix.PubSub.subscribe(Setlistify.PubSub, "user:#{user2_id}")

      # Mock the refresh_token API call for user1
      expect(Setlistify.Spotify.API.MockClient, :refresh_token, fn refresh_token ->
        assert refresh_token == @refresh_token

        {:ok,
         %{
           access_token: "user1_new_token",
           refresh_token: @refresh_token,
           expires_in: 3600
         }}
      end)

      # Start session for user1
      user1_session = %UserSession{
        access_token: initial_token.access_token,
        refresh_token: initial_token.refresh_token,
        expires_at: System.system_time(:second) + initial_token.expires_in,
        user_id: user1_id,
        username: "test_user"
      }

      {:ok, pid} = SessionManager.start_link({user1_id, user1_session})

      # Allow the mock to be called from the session process
      allow(Setlistify.Spotify.API.MockClient, self(), pid)

      # Trigger a refresh for user1
      assert {:ok, session} = SessionManager.refresh_session(user1_id)
      assert session.access_token == "user1_new_token"

      # Should NOT receive a broadcast on user2's channel
      refute_receive {:token_refreshed, _}, 100
    end

    test "different users receive their own broadcasts", %{initial_token: initial_token} do
      user1_id = unique_user_id()
      user2_id = unique_user_id()

      # Subscribe to both channels
      Phoenix.PubSub.subscribe(Setlistify.PubSub, "user:#{user1_id}")
      Phoenix.PubSub.subscribe(Setlistify.PubSub, "user:#{user2_id}")

      # Mock refresh for user1
      expect(Setlistify.Spotify.API.MockClient, :refresh_token, 1, fn "user1_refresh" ->
        {:ok,
         %{
           access_token: "user1_new_token",
           refresh_token: "user1_refresh",
           expires_in: 3600
         }}
      end)

      # Mock refresh for user2
      expect(Setlistify.Spotify.API.MockClient, :refresh_token, 1, fn "user2_refresh" ->
        {:ok,
         %{
           access_token: "user2_new_token",
           refresh_token: "user2_refresh",
           expires_in: 3600
         }}
      end)

      # Start sessions
      user1_tokens = %{initial_token | refresh_token: "user1_refresh"}
      user2_tokens = %{initial_token | refresh_token: "user2_refresh"}

      user1_session = %UserSession{
        access_token: user1_tokens.access_token,
        refresh_token: user1_tokens.refresh_token,
        expires_at: System.system_time(:second) + user1_tokens.expires_in,
        user_id: user1_id,
        username: "test_user1"
      }

      user2_session = %UserSession{
        access_token: user2_tokens.access_token,
        refresh_token: user2_tokens.refresh_token,
        expires_at: System.system_time(:second) + user2_tokens.expires_in,
        user_id: user2_id,
        username: "test_user2"
      }

      {:ok, pid1} = SessionManager.start_link({user1_id, user1_session})
      {:ok, pid2} = SessionManager.start_link({user2_id, user2_session})

      # Allow the mocks to be called from the session processes
      allow(Setlistify.Spotify.API.MockClient, self(), pid1)
      allow(Setlistify.Spotify.API.MockClient, self(), pid2)

      # Trigger refreshes
      assert {:ok, session1} = SessionManager.refresh_session(user1_id)
      assert session1.access_token == "user1_new_token"
      assert {:ok, session2} = SessionManager.refresh_session(user2_id)
      assert session2.access_token == "user2_new_token"

      # Should receive correct broadcasts for each user
      assert_receive {:token_refreshed,
                      %UserSession{
                        access_token: "user1_new_token",
                        user_id: ^user1_id
                      }}

      assert_receive {:token_refreshed,
                      %UserSession{
                        access_token: "user2_new_token",
                        user_id: ^user2_id
                      }}
    end
  end
end
