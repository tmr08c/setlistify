defmodule Setlistify.Spotify.TokenSupervisorTest do
  use ExUnit.Case, async: true
  alias Setlistify.Spotify.TokenSupervisor

  # Generate unique user IDs for each test to prevent test pollution
  def uniq_user_id(), do: "user_#{System.unique_integer([:positive])}"

  @initial_tokens %{
    access_token: "initial_access_token",
    refresh_token: "refresh_token",
    expires_in: 3600
  }

  setup do
    # Just generate a unique user ID for each test
    user_id = uniq_user_id()

    {:ok, %{user_id: user_id}}
  end

  describe "start_user_token/2" do
    test "starts a new token process", %{user_id: user_id} do
      # Verify the process doesn't exist before starting
      assert {:error, :not_found} = TokenSupervisor.get_token(user_id)

      # Now start a fresh process
      assert {:ok, pid} = TokenSupervisor.start_user_token(user_id, @initial_tokens)
      assert Process.alive?(pid)

      # Verify we can get the token
      assert {:ok, "initial_access_token"} = TokenSupervisor.get_token(user_id)
    end

    test "can start multiple user token processes", %{user_id: _user_id} do
      user1 = uniq_user_id()
      user2 = uniq_user_id()

      assert {:ok, pid1} = TokenSupervisor.start_user_token(user1, @initial_tokens)
      assert {:ok, pid2} = TokenSupervisor.start_user_token(user2, @initial_tokens)

      assert Process.alive?(pid1)
      assert Process.alive?(pid2)
      assert pid1 != pid2
    end
  end

  describe "stop_user_token/1" do
    test "stops the token process", %{user_id: user_id} do
      {:ok, pid} = TokenSupervisor.start_user_token(user_id, @initial_tokens)
      assert :ok = TokenSupervisor.stop_user_token(user_id)
      refute Process.alive?(pid)
    end

    test "returns error when process not found", %{user_id: _user_id} do
      nonexistent_user = uniq_user_id()
      assert {:error, :not_found} = TokenSupervisor.stop_user_token(nonexistent_user)
    end
  end

  describe "get_token/1" do
    test "retrieves token from running process", %{user_id: user_id} do
      {:ok, _pid} = TokenSupervisor.start_user_token(user_id, @initial_tokens)
      assert {:ok, "initial_access_token"} = TokenSupervisor.get_token(user_id)
    end

    test "returns error when process not found for get_token", %{user_id: _user_id} do
      nonexistent_user = uniq_user_id()
      assert {:error, :not_found} = TokenSupervisor.get_token(nonexistent_user)
    end
  end
end
