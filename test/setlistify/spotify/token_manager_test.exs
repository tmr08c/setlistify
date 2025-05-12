defmodule Setlistify.Spotify.TokenManagerTest do
  use ExUnit.Case, async: true
  alias Setlistify.Spotify.TokenManager

  @user_id "test_user"
  @initial_tokens %{
    access_token: "initial_access_token",
    refresh_token: "refresh_token",
    expires_in: 3600
  }

  setup do
    # Start the Registry and DynamicSupervisor for each test
    start_supervised!(Registry)
    start_supervised!({Registry, keys: :unique, name: Setlistify.UserTokenRegistry})
    start_supervised!({DynamicSupervisor, name: Setlistify.UserTokenSupervisor})

    :ok
  end

  describe "start_link/1" do
    test "starts a new token manager process" do
      assert {:ok, pid} = TokenManager.start_link({@user_id, @initial_tokens})
      assert Process.alive?(pid)
    end

    test "registers process with Registry" do
      {:ok, pid} = TokenManager.start_link({@user_id, @initial_tokens})
      assert [{^pid, nil}] = Registry.lookup(Setlistify.UserTokenRegistry, @user_id)
    end
  end

  describe "get_token/1" do
    test "returns current access token" do
      {:ok, _pid} = TokenManager.start_link({@user_id, @initial_tokens})
      assert {:ok, "initial_access_token"} = TokenManager.get_token(@user_id)
    end

    test "returns error when process not found" do
      assert {:error, :not_found} = TokenManager.get_token("nonexistent_user")
    end
  end

  describe "refresh_token/1" do
    test "refreshes token successfully" do
      {:ok, _pid} = TokenManager.start_link({@user_id, @initial_tokens})
      new_token = "new_access_token"

      # TODO Update with Req.Test
      # Mock the Spotify API response
      expect(Req, :post, fn "https://accounts.spotify.com/api/token", _opts ->
        {:ok,
         %{
           status: 200,
           body: %{
             "access_token" => new_token,
             "expires_in" => 3600
           }
         }}
      end)

      assert {:ok, ^new_token} = TokenManager.refresh_token(@user_id)
    end

    test "terminates process on refresh failure" do
      {:ok, pid} = TokenManager.start_link({@user_id, @initial_tokens})

      # TODO Update with Req.Test
      # Mock failed refresh
      expect(Req, :post, fn "https://accounts.spotify.com/api/token", _opts ->
        {:ok, %{status: 401}}
      end)

      assert {:error, :invalid_token} = TokenManager.refresh_token(@user_id)
      refute Process.alive?(pid)
    end
  end

  describe "automatic refresh" do
    # TODO check that this works
    @tag :capture_log
    test "schedules token refresh before expiration" do
      # Use a short expiration time for testing
      tokens = %{@initial_tokens | expires_in: 2}
      {:ok, pid} = TokenManager.start_link({@user_id, tokens})

      # TODO update to Req.Test
      # Question: should this be before we start the link?
      # Mock successful refresh
      expect(Req, :post, fn "https://accounts.spotify.com/api/token", _opts ->
        {:ok,
         %{
           status: 200,
           body: %{
             "access_token" => "refreshed_token",
             "expires_in" => 3600
           }
         }}
      end)

      # Wait for the refresh to happen
      Process.sleep(2_500)
      assert Process.alive?(pid)

      # Verify the token was refreshed
      assert {:ok, "refreshed_token"} = TokenManager.get_token(@user_id)

      # IDEA: We could possibly have this test that the message is sent to itself (before the expires in?)
      # And test the refreshing more directly?
    end
  end

  # TODO Not sure if we need this. Maybe we should be using the API client
  # Helper function to set up mocks
  defp expect(module, function, times, callback) do
    :ok = Application.put_env(:setlistify, :spotify_client_id, "test_client_id")
    :ok = Application.put_env(:setlistify, :spotify_client_secret, "test_client_secret")
    Mox.expect(module, function, times, callback)
  end
end
