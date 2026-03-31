defmodule Setlistify.AppleMusic.SessionManagerTest do
  use ExUnit.Case, async: true

  import Setlistify.Test.RegistryHelpers

  alias Setlistify.AppleMusic.{SessionManager, UserSession}

  setup do
    user_id = unique_user_id()

    session = %UserSession{
      user_token: "test_user_token",
      user_id: user_id,
      storefront: "us"
    }

    {:ok, %{user_id: user_id, session: session}}
  end

  describe "start_link/1" do
    test "starts a new session manager process", %{user_id: user_id, session: session} do
      assert {:ok, pid} = SessionManager.start_link({user_id, session})
      assert Process.alive?(pid)
    end

    test "registers process under {:apple_music, user_id}", %{user_id: user_id, session: session} do
      {:ok, pid} = SessionManager.start_link({user_id, session})
      registry_pid = assert_in_registry({:apple_music, user_id})
      assert registry_pid == pid
    end
  end

  describe "get_session/1" do
    test "returns the stored session", %{user_id: user_id, session: session} do
      {:ok, _pid} = SessionManager.start_link({user_id, session})
      assert {:ok, ^session} = SessionManager.get_session(user_id)
    end

    test "returns :not_found when no process exists", %{user_id: user_id} do
      assert {:error, :not_found} = SessionManager.get_session(user_id)
    end
  end

  describe "stop/1" do
    test "terminates the process", %{user_id: user_id, session: session} do
      {:ok, pid} = SessionManager.start_link({user_id, session})
      assert Process.alive?(pid)
      assert :ok = SessionManager.stop(user_id)
      refute Process.alive?(pid)
    end

    test "returns :not_found when no process exists", %{user_id: user_id} do
      assert {:error, :not_found} = SessionManager.stop(user_id)
    end
  end

  describe "lookup/1" do
    test "returns {:ok, pid} when process is registered", %{user_id: user_id, session: session} do
      {:ok, pid} = SessionManager.start_link({user_id, session})
      assert {:ok, ^pid} = SessionManager.lookup(user_id)
    end

    test "returns :error when no process is registered", %{user_id: user_id} do
      assert :error = SessionManager.lookup(user_id)
    end
  end
end
