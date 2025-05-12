defmodule Setlistify.Spotify.TokenSupervisorTest do
  use ExUnit.Case, async: true
  alias Setlistify.Spotify.TokenSupervisor

  @user_id "test_user"
  @initial_tokens %{
    access_token: "initial_access_token",
    refresh_token: "refresh_token",
    expires_in: 3600
  }

  setup do
    start_supervised!({Registry, keys: :unique, name: Setlistify.UserTokenRegistry})
    start_supervised!({DynamicSupervisor, name: Setlistify.UserTokenSupervisor})
    :ok
  end

  describe "start_user_token/2" do
    test "starts a new token process" do
      assert {:ok, pid} = TokenSupervisor.start_user_token(@user_id, @initial_tokens)
      assert Process.alive?(pid)
      assert {:ok, "initial_access_token"} = TokenSupervisor.get_token(@user_id)
    end

    test "can start multiple user token processes" do
      user1 = "user1"
      user2 = "user2"

      assert {:ok, pid1} = TokenSupervisor.start_user_token(user1, @initial_tokens)
      assert {:ok, pid2} = TokenSupervisor.start_user_token(user2, @initial_tokens)

      assert Process.alive?(pid1)
      assert Process.alive?(pid2)
      assert pid1 != pid2
    end
  end

  describe "stop_user_token/1" do
    test "stops the token process" do
      {:ok, pid} = TokenSupervisor.start_user_token(@user_id, @initial_tokens)
      assert :ok = TokenSupervisor.stop_user_token(@user_id)
      refute Process.alive?(pid)
    end

    test "returns error when process not found" do
      assert {:error, :not_found} = TokenSupervisor.stop_user_token("nonexistent_user")
    end
  end

  describe "get_token/1" do
    test "retrieves token from running process" do
      {:ok, _pid} = TokenSupervisor.start_user_token(@user_id, @initial_tokens)
      assert {:ok, "initial_access_token"} = TokenSupervisor.get_token(@user_id)
    end

    test "returns error when process not found" do
      assert {:error, :not_found} = TokenSupervisor.get_token("nonexistent_user")
    end
  end
end