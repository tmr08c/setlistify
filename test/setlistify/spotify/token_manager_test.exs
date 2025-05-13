defmodule Setlistify.Spotify.TokenManagerTest do
  use ExUnit.Case, async: true
  import Hammox
  alias Setlistify.Spotify.TokenManager

  @user_id "test_user"
  @initial_token %{
    access_token: "initial_access_token",
    refresh_token: "refresh_token",
    expires_in: 3600
  }

  setup :verify_on_exit!

  setup do
    # TODO I'm not sure if we should do this manually, or be relying on the
    # applicaton start up process
    #
    # Start the Registry and DynamicSupervisor for each test
    # start_supervised!(Registry)
    # start_supervised!({Registry, keys: :unique, name: Setlistify.UserTokenRegistry})
    # start_supervised!({DynamicSupervisor, name: Setlistify.UserTokenSupervisor})

    :ok
  end

  describe "start_link/1" do
    test "starts a new token manager process" do
      assert {:ok, pid} = TokenManager.start_link({@user_id, @initial_token})
      assert Process.alive?(pid)
    end

    test "registers process with Registry" do
      {:ok, pid} = TokenManager.start_link({@user_id, @initial_token})
      assert [{^pid, nil}] = Registry.lookup(Setlistify.UserTokenRegistry, @user_id)
    end
  end

  describe "get_token/1" do
    test "returns current access token" do
      {:ok, _pid} = TokenManager.start_link({@user_id, @initial_token})
      assert {:ok, "initial_access_token"} = TokenManager.get_token(@user_id)
    end

    test "returns error when process not found" do
      assert {:error, :not_found} = TokenManager.get_token("nonexistent_user")
    end
  end

  describe "refresh_token/1" do
    test "refreshes token successfully" do
      {:ok, pid} = TokenManager.start_link({@user_id, @initial_token})
      new_token = "new_access_token"

      expect(Setlistify.Spotify.API.MockClient, :refresh_token, fn refresh_token ->
        assert refresh_token == @initial_token.refresh_token

        {:ok,
         %{
           access_token: new_token,
           refresh_token: refresh_token,
           expires_in: 3600
         }}
      end)

      allow(Setlistify.Spotify.API.MockClient, self(), pid)

      assert {:ok, ^new_token} = TokenManager.refresh_token(@user_id)
    end

    @tag :capture_log
    test "terminates process on refresh failure" do
      {:ok, pid} = TokenManager.start_link({@user_id, @initial_token})

      expect(Setlistify.Spotify.API.MockClient, :refresh_token, fn refresh_token ->
        assert refresh_token == @initial_token.refresh_token
        {:error, :invalid_token}
      end)

      allow(Setlistify.Spotify.API.MockClient, self(), pid)

      assert {:error, :invalid_token} = TokenManager.refresh_token(@user_id)
      refute Process.alive?(pid)
    end
  end

  describe "automatic refresh" do
    test "schedules token refresh before expiration" do
      expect(Setlistify.Spotify.API.MockClient, :refresh_token, fn refresh_token ->
        assert refresh_token == @initial_token.refresh_token

        {:ok,
         %{
           access_token: "refreshed_token",
           refresh_token: refresh_token,
           expires_in: 3600
         }}
      end)

      allow(Setlistify.Spotify.API.MockClient, self(), fn ->
        [{pid, _}] = Registry.lookup(Setlistify.UserTokenRegistry, @user_id)

        pid
      end)

      # Set `expires_in` to short duration, something quicker than
      # @refresh_threshold, so we will attempt to refresh right away.
      tokens = %{@initial_token | expires_in: 2}
      {:ok, pid} = TokenManager.start_link({@user_id, tokens})

      # Wait for the refresh to happen
      assert Process.alive?(pid)

      # Verify the token was refreshed
      assert {:ok, "refreshed_token"} = TokenManager.get_token(@user_id)
    end
  end
end
