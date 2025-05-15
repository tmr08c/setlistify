defmodule Setlistify.Spotify.SessionManagerTest do
  use ExUnit.Case, async: true

  import Hammox
  import Setlistify.Test.RegistryHelpers

  alias Setlistify.Spotify.SessionManager

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
      assert {:ok, pid} = SessionManager.start_link({user_id, initial_token})
      assert Process.alive?(pid)
    end

    test "registers process with Registry", %{user_id: user_id, initial_token: initial_token} do
      {:ok, pid} = SessionManager.start_link({user_id, initial_token})
      registry_pid = assert_in_registry(user_id)
      assert registry_pid == pid
    end
  end

  describe "get_token/1" do
    test "returns current access token", %{user_id: user_id, initial_token: initial_token} do
      {:ok, _pid} = SessionManager.start_link({user_id, initial_token})
      assert {:ok, "initial_access_token"} = SessionManager.get_token(user_id)
    end

    test "returns error when process not found", %{user_id: _user_id} do
      nonexistent_user = unique_user_id()
      assert {:error, :not_found} = SessionManager.get_token(nonexistent_user)
    end
  end

  describe "refresh_token/1" do
    test "refreshes token successfully", %{user_id: user_id, initial_token: initial_token} do
      {:ok, pid} = SessionManager.start_link({user_id, initial_token})
      new_token = "new_access_token"

      expect(Setlistify.Spotify.API.MockClient, :refresh_token, fn refresh_token ->
        assert refresh_token == initial_token.refresh_token

        {:ok,
         %{
           access_token: new_token,
           refresh_token: refresh_token,
           expires_in: 3600
         }}
      end)

      allow(Setlistify.Spotify.API.MockClient, self(), pid)

      assert {:ok, ^new_token} = SessionManager.refresh_token(user_id)
    end

    @tag :capture_log
    test "terminates process on refresh failure", %{
      user_id: user_id,
      initial_token: initial_token
    } do
      {:ok, pid} = SessionManager.start_link({user_id, initial_token})

      expect(Setlistify.Spotify.API.MockClient, :refresh_token, fn refresh_token ->
        assert refresh_token == initial_token.refresh_token
        {:error, :invalid_token}
      end)

      allow(Setlistify.Spotify.API.MockClient, self(), pid)

      assert {:error, :invalid_token} = SessionManager.refresh_token(user_id)
      refute Process.alive?(pid)
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
        pid = assert_in_registry(user_id, fail_on_timeout: false)
        if is_nil(pid), do: self(), else: pid
      end)

      # Set `expires_in` to short duration, something quicker than
      # @refresh_threshold, so we will attempt to refresh right away.
      token = %{initial_token | expires_in: 1}

      # Start the session process which should trigger a refresh immediately
      {:ok, pid} = SessionManager.start_link({user_id, token})

      assert Process.alive?(pid)

      # Verify the token was refreshed
      assert {:ok, "refreshed_token"} = SessionManager.get_token(user_id)
    end
  end
end
