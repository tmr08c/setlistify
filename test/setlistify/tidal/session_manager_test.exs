defmodule Setlistify.Tidal.SessionManagerTest do
  use ExUnit.Case, async: true

  import Hammox
  import Setlistify.Test.RegistryHelpers

  alias Setlistify.Tidal.API.MockClient
  alias Setlistify.Tidal.SessionManager
  alias Setlistify.Tidal.UserSession

  @refresh_token "test_refresh_token"

  setup :verify_on_exit!

  setup do
    user_id = unique_user_id()

    session = %UserSession{
      access_token: "initial_access_token",
      refresh_token: @refresh_token,
      expires_at: System.system_time(:second) + 14_400,
      user_id: user_id,
      country_code: "US"
    }

    {:ok, %{user_id: user_id, session: session}}
  end

  describe "start_link/1" do
    test "starts and registers a session manager process", %{user_id: user_id, session: session} do
      assert {:ok, pid} = SessionManager.start_link({user_id, session})
      assert Process.alive?(pid)

      registry_pid = assert_in_registry({:tidal, user_id})
      assert registry_pid == pid
    end
  end

  describe "get_token/1" do
    test "returns the current access token", %{user_id: user_id, session: session} do
      {:ok, _pid} = SessionManager.start_link({user_id, session})
      assert {:ok, "initial_access_token"} = SessionManager.get_token(user_id)
    end

    test "returns error when process not found" do
      assert {:error, :not_found} = SessionManager.get_token(unique_user_id())
    end
  end

  describe "get_session/1" do
    test "returns the UserSession struct with country_code", %{user_id: user_id, session: session} do
      {:ok, _pid} = SessionManager.start_link({user_id, session})

      assert {:ok, returned} = SessionManager.get_session(user_id)
      assert %UserSession{} = returned
      assert returned.access_token == "initial_access_token"
      assert returned.refresh_token == @refresh_token
      assert returned.user_id == user_id
      assert returned.country_code == "US"
    end

    test "returns error when process not found" do
      assert {:error, :not_found} = SessionManager.get_session(unique_user_id())
    end
  end

  describe "stop/1" do
    test "terminates the process", %{user_id: user_id, session: session} do
      {:ok, pid} = SessionManager.start_link({user_id, session})
      assert :ok = SessionManager.stop(user_id)
      refute Process.alive?(pid)
    end

    test "returns :not_found when no process exists" do
      assert {:error, :not_found} = SessionManager.stop(unique_user_id())
    end
  end

  describe "lookup/1" do
    test "returns {:ok, pid} when registered", %{user_id: user_id, session: session} do
      {:ok, pid} = SessionManager.start_link({user_id, session})
      assert {:ok, ^pid} = SessionManager.lookup(user_id)
    end

    test "returns :error when not registered" do
      assert :error = SessionManager.lookup(unique_user_id())
    end
  end

  describe "refresh_session/1" do
    test "refreshes the access token and preserves the (non-rotated) refresh token + country_code",
         %{user_id: user_id, session: session} do
      {:ok, pid} = SessionManager.start_link({user_id, session})

      # Tidal's refresh response carries NO refresh_token — only a new access
      # token and expiry. The manager must keep the existing refresh token.
      expect(MockClient, :refresh_token, fn refresh_token ->
        assert refresh_token == @refresh_token
        {:ok, %{access_token: "new_access_token", expires_in: 14_400}}
      end)

      allow(MockClient, self(), pid)

      assert {:ok, refreshed} = SessionManager.refresh_session(user_id)
      assert %UserSession{} = refreshed
      assert refreshed.access_token == "new_access_token"
      assert refreshed.refresh_token == @refresh_token
      assert refreshed.country_code == "US"
      assert refreshed.user_id == user_id
      assert refreshed.expires_at > System.system_time(:second)
    end

    @tag :capture_log
    test "terminates the process on refresh failure", %{user_id: user_id, session: session} do
      {:ok, pid} = SessionManager.start_link({user_id, session})

      expect(MockClient, :refresh_token, fn _refresh_token -> {:error, :invalid_token} end)
      allow(MockClient, self(), pid)

      assert {:error, :invalid_token} = SessionManager.refresh_session(user_id)
      refute Process.alive?(pid)
    end

    test "returns error when process not found" do
      assert {:error, :not_found} = SessionManager.refresh_session(unique_user_id())
    end
  end

  describe "automatic refresh" do
    test "schedules a refresh that fires before expiration", %{user_id: user_id, session: session} do
      expect(MockClient, :refresh_token, fn refresh_token ->
        assert refresh_token == @refresh_token
        {:ok, %{access_token: "refreshed_token", expires_in: 14_400}}
      end)

      allow(MockClient, self(), fn ->
        pid = assert_in_registry({:tidal, user_id}, fail_on_timeout: false)
        if is_nil(pid), do: self(), else: pid
      end)

      # Force an immediate refresh: with a tiny TTL the scheduled delay is
      # negative, so the manager sends itself :refresh_token right away.
      short_lived = %{session | expires_at: System.system_time(:second) + 1}

      {:ok, pid} = SessionManager.start_link({user_id, short_lived})
      assert Process.alive?(pid)

      assert {:ok, "refreshed_token"} = SessionManager.get_token(user_id)
    end
  end

  describe "PubSub broadcasting" do
    test "broadcasts the refreshed session on the user's channel", %{
      user_id: user_id,
      session: session
    } do
      Phoenix.PubSub.subscribe(Setlistify.PubSub, "user:#{user_id}")

      expect(MockClient, :refresh_token, fn _refresh_token ->
        {:ok, %{access_token: "new_access_token", expires_in: 14_400}}
      end)

      {:ok, pid} = SessionManager.start_link({user_id, session})
      allow(MockClient, self(), pid)

      assert {:ok, refreshed} = SessionManager.refresh_session(user_id)
      assert refreshed.access_token == "new_access_token"

      assert_receive {:token_refreshed,
                      %UserSession{
                        access_token: "new_access_token",
                        refresh_token: @refresh_token,
                        country_code: "US",
                        user_id: ^user_id
                      }}
    end

    test "does not broadcast to other users' channels", %{session: session} do
      user1_id = unique_user_id()
      user2_id = unique_user_id()

      Phoenix.PubSub.subscribe(Setlistify.PubSub, "user:#{user2_id}")

      expect(MockClient, :refresh_token, fn _refresh_token ->
        {:ok, %{access_token: "user1_new_token", expires_in: 14_400}}
      end)

      user1_session = %{session | user_id: user1_id}
      {:ok, pid} = SessionManager.start_link({user1_id, user1_session})
      allow(MockClient, self(), pid)

      assert {:ok, _} = SessionManager.refresh_session(user1_id)

      refute_receive {:token_refreshed, _}, 100
    end
  end
end
