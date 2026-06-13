defmodule Setlistify.Tidal.SessionSupervisorTest do
  use ExUnit.Case, async: true

  import Setlistify.Test.RegistryHelpers

  alias Setlistify.Tidal.SessionSupervisor
  alias Setlistify.Tidal.UserSession

  setup do
    user_id = unique_user_id()

    session = %UserSession{
      access_token: "initial_access_token",
      refresh_token: "refresh_token",
      expires_at: System.system_time(:second) + 14_400,
      user_id: user_id,
      country_code: "US"
    }

    {:ok, %{user_id: user_id, session: session}}
  end

  describe "start_user_token/2" do
    test "starts a new token process", %{user_id: user_id, session: session} do
      assert {:error, :not_found} = SessionSupervisor.get_token(user_id)

      assert {:ok, pid} = SessionSupervisor.start_user_token(user_id, session)
      assert Process.alive?(pid)

      assert {:ok, "initial_access_token"} = SessionSupervisor.get_token(user_id)
    end

    test "can start multiple user token processes", %{session: session} do
      user1 = unique_user_id()
      user2 = unique_user_id()

      assert {:ok, pid1} = SessionSupervisor.start_user_token(user1, %{session | user_id: user1})
      assert {:ok, pid2} = SessionSupervisor.start_user_token(user2, %{session | user_id: user2})

      assert Process.alive?(pid1)
      assert Process.alive?(pid2)
      assert pid1 != pid2
    end
  end

  describe "stop_user_token/1" do
    test "stops the token process and does not restart it", %{
      user_id: user_id,
      session: session
    } do
      {:ok, pid} = SessionSupervisor.start_user_token(user_id, session)
      assert Process.alive?(pid)

      assert :ok = SessionSupervisor.stop_user_token(user_id)
      refute Process.alive?(pid)

      Process.sleep(1)
      refute_in_registry({:tidal, user_id})
    end

    test "returns error when process not found" do
      assert {:error, :not_found} = SessionSupervisor.stop_user_token(unique_user_id())
    end
  end

  describe "get_token/1" do
    test "retrieves the token from a running process", %{user_id: user_id, session: session} do
      {:ok, _pid} = SessionSupervisor.start_user_token(user_id, session)
      assert {:ok, "initial_access_token"} = SessionSupervisor.get_token(user_id)
    end

    test "returns error when process not found" do
      assert {:error, :not_found} = SessionSupervisor.get_token(unique_user_id())
    end
  end
end
