defmodule SetlistifyWeb.Plugs.RestoreSpotifyTokenTest do
  use SetlistifyWeb.ConnCase, async: true

  import Hammox

  alias SetlistifyWeb.Plugs.RestoreSpotifyToken
  alias Setlistify.Spotify.TokenManager

  @refresh_token "test_refresh_token"

  # Verify all mocks at the end of each test
  setup :verify_on_exit!

  setup do
    # Generate a unique user ID for this test
    {:ok, %{username: unique_user_id()}}
  end

  describe "call/2" do
    test "does nothing when no user in session", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> RestoreSpotifyToken.call([])

      refute conn.halted
    end

    test "does nothing when token process exists", %{conn: conn, username: username} do
      tokens = %{access_token: "test_token", refresh_token: @refresh_token, expires_in: 3600}

      # Start the token manager or get the pid if it already exists
      _pid =
        case TokenManager.start_link({username, tokens}) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> put_session("user", %{"username" => username})
        |> RestoreSpotifyToken.call([])

      refute conn.halted
    end

    test "restores token process from valid refresh token", %{conn: conn, username: username} do
      # Ensure there is no existing token process
      case Registry.lookup(Setlistify.UserTokenRegistry, username) do
        [{pid, _}] -> GenServer.stop(pid)
        [] -> :ok
      end

      encrypted_token = Phoenix.Token.sign(SetlistifyWeb.Endpoint, "user auth", @refresh_token)

      # Mock successful token refresh using the API.MockClient
      expect(Setlistify.Spotify.API.MockClient, :refresh_token, fn token ->
        assert token == @refresh_token

        {:ok,
         %{
           access_token: "new_token",
           refresh_token: @refresh_token,
           expires_in: 3600
         }}
      end)
      
      # Allow the mock to be called from the token process
      allow(Setlistify.Spotify.API.MockClient, self(), fn ->
        # Wait for the process to be registered and return it
        # This avoids flakiness issues where the Registry lookup might happen
        # before the process is registered
        # In these tests, we're creating the process after setting up the mock,
        # so we don't want to fail if the process isn't registered yet
        pid = assert_in_registry(username, fail_on_timeout: false)
        if is_nil(pid), do: self(), else: pid
      end)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> put_session("user", %{"username" => username})
        |> put_session(:refresh_token, encrypted_token)
        |> RestoreSpotifyToken.call([])

      refute conn.halted

      # Verify the token process was created with the expected token
      {:ok, token} = TokenManager.get_token(username)
      assert token == "new_token"
    end

    test "redirects and clears session on refresh failure", %{conn: conn, username: username} do
      encrypted_token = Phoenix.Token.sign(SetlistifyWeb.Endpoint, "user auth", @refresh_token)

      # Mock failed token refresh using the API.MockClient
      expect(Setlistify.Spotify.API.MockClient, :refresh_token, fn token ->
        assert token == @refresh_token
        {:error, :invalid_token}
      end)
      
      # Allow the mock to be called from the token process
      allow(Setlistify.Spotify.API.MockClient, self(), fn ->
        # Wait for the process to be registered and return it
        # This avoids flakiness issues where the Registry lookup might happen
        # before the process is registered
        # In these tests, we're creating the process after setting up the mock,
        # so we don't want to fail if the process isn't registered yet
        pid = assert_in_registry(username, fail_on_timeout: false)
        if is_nil(pid), do: self(), else: pid
      end)

      # Ensure there is no existing token process
      assert [] == Registry.lookup(Setlistify.UserTokenRegistry, username)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> put_session("user", %{"username" => username})
        |> put_session(:refresh_token, encrypted_token)
        |> RestoreSpotifyToken.call([])

      assert conn.halted
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "session has expired"
      assert redirected_to(conn) == "/"

      # After a refresh failure, the token should not exist
      assert {:error, :not_found} = TokenManager.get_token(username)
    end
  end
end
