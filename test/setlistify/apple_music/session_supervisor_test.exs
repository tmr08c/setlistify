defmodule Setlistify.AppleMusic.SessionSupervisorTest do
  use ExUnit.Case, async: true

  import Setlistify.Test.RegistryHelpers

  alias Setlistify.AppleMusic.SessionSupervisor
  alias Setlistify.AppleMusic.UserSession

  setup do
    user_id = unique_user_id()

    user_session = %UserSession{
      user_token: "apple_music_token",
      user_id: user_id,
      storefront: "us"
    }

    {:ok, %{user_id: user_id, user_session: user_session}}
  end

  describe "start_user_token/2" do
    test "starts a new session process", %{user_id: user_id, user_session: user_session} do
      assert {:error, :not_found} = SessionSupervisor.get_session(user_id)

      assert {:ok, pid} = SessionSupervisor.start_user_token(user_id, user_session)
      assert Process.alive?(pid)

      assert {:ok, ^user_session} = SessionSupervisor.get_session(user_id)
    end

    test "can start multiple user session processes", %{user_session: user_session} do
      user1 = unique_user_id()
      user2 = unique_user_id()

      session1 = %{user_session | user_id: user1}
      session2 = %{user_session | user_id: user2}

      assert {:ok, pid1} = SessionSupervisor.start_user_token(user1, session1)
      assert {:ok, pid2} = SessionSupervisor.start_user_token(user2, session2)

      assert Process.alive?(pid1)
      assert Process.alive?(pid2)
      assert pid1 != pid2
    end

    @tag :capture_log
    test "handles already_started gracefully", %{user_id: user_id, user_session: user_session} do
      assert {:ok, pid1} = SessionSupervisor.start_user_token(user_id, user_session)
      assert {:ok, pid2} = SessionSupervisor.start_user_token(user_id, user_session)

      assert pid1 == pid2
      assert Process.alive?(pid1)
    end
  end

  describe "stop_user_token/1" do
    test "stops the session process", %{user_id: user_id, user_session: user_session} do
      {:ok, pid} = SessionSupervisor.start_user_token(user_id, user_session)
      assert :ok = SessionSupervisor.stop_user_token(user_id)
      refute Process.alive?(pid)
    end

    test "returns error when process not found" do
      nonexistent_user = unique_user_id()
      assert {:error, :not_found} = SessionSupervisor.stop_user_token(nonexistent_user)
    end

    test "doesn't automatically start a new process after stopping", %{
      user_id: user_id,
      user_session: user_session
    } do
      {:ok, pid} = SessionSupervisor.start_user_token(user_id, user_session)
      assert Process.alive?(pid)

      assert {:ok, _session} = SessionSupervisor.get_session(user_id)

      assert :ok = SessionSupervisor.stop_user_token(user_id)
      refute Process.alive?(pid)

      Process.sleep(1)

      refute_in_registry({:apple_music, user_id})
    end
  end

  describe "get_session/1" do
    test "retrieves session from running process", %{user_id: user_id, user_session: user_session} do
      {:ok, _pid} = SessionSupervisor.start_user_token(user_id, user_session)
      assert {:ok, ^user_session} = SessionSupervisor.get_session(user_id)
    end

    test "returns error when process not found" do
      nonexistent_user = unique_user_id()
      assert {:error, :not_found} = SessionSupervisor.get_session(nonexistent_user)
    end
  end
end
