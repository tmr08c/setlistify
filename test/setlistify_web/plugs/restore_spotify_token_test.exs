defmodule SetlistifyWeb.Plugs.RestoreSpotifyTokenTest do
  use SetlistifyWeb.ConnCase, async: true

  import Hammox

  alias SetlistifyWeb.Plugs.RestoreSpotifyToken
  alias Setlistify.Spotify.SessionManager

  @refresh_token "test_refresh_token"

  # Verify all mocks at the end of each test
  setup :verify_on_exit!

  setup do
    # Generate a unique user ID for this test
    user_id = unique_user_id()
    {:ok, %{user_id: user_id}}
  end

  describe "call/2" do
    test "does nothing when no user_id in session", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> RestoreSpotifyToken.call([])

      refute conn.halted
    end

    test "does nothing when session process exists", %{conn: conn, user_id: user_id} do
      session = %Setlistify.Spotify.UserSession{
        access_token: "test_token",
        refresh_token: @refresh_token,
        expires_at: System.system_time(:second) + 3600,
        user_id: user_id,
        username: "test_user"
      }

      # Start the session manager or get the pid if it already exists
      _pid =
        case SessionManager.start_link({user_id, session}) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> put_session(:auth_provider, "spotify")
        |> put_session(:user_id, user_id)
        |> RestoreSpotifyToken.call([])

      refute conn.halted
    end

    test "restores session process from valid refresh token", %{conn: conn, user_id: user_id} do
      # Ensure there is no existing session process
      case Registry.lookup(Setlistify.UserSessionRegistry, {:spotify, user_id}) do
        [{pid, _}] -> GenServer.stop(pid)
        [] -> :ok
      end

      encrypted_token = Phoenix.Token.sign(SetlistifyWeb.Endpoint, "user auth", @refresh_token)

      # Mock the new refresh_to_user_session function
      expect(Setlistify.Spotify.API.MockClient, :refresh_to_user_session, fn token ->
        assert token == @refresh_token

        {:ok,
         %Setlistify.Spotify.UserSession{
           access_token: "new_token",
           refresh_token: @refresh_token,
           expires_at: System.system_time(:second) + 3600,
           user_id: user_id,
           username: "test_username"
         }}
      end)

      # Allow the mock to be called from the session process
      allow(Setlistify.Spotify.API.MockClient, self(), fn ->
        pid = assert_in_registry({:spotify, user_id}, fail_on_timeout: false)
        if is_nil(pid), do: self(), else: pid
      end)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> put_session(:auth_provider, "spotify")
        |> put_session(:user_id, user_id)
        |> put_session(:refresh_token, encrypted_token)
        |> RestoreSpotifyToken.call([])

      refute conn.halted

      # Verify the session process was created with a UserSession
      {:ok, session} = SessionManager.get_session(user_id)
      assert %Setlistify.Spotify.UserSession{} = session
      assert session.access_token == "new_token"
      assert session.username == "test_username"
      assert session.user_id == user_id
    end

    test "clears session and continues on refresh failure", %{conn: conn, user_id: user_id} do
      encrypted_token = Phoenix.Token.sign(SetlistifyWeb.Endpoint, "user auth", @refresh_token)

      # Mock failed token refresh using the new function
      expect(Setlistify.Spotify.API.MockClient, :refresh_to_user_session, fn token ->
        assert token == @refresh_token
        {:error, :invalid_token}
      end)

      # Allow the mock to be called from the session process
      allow(Setlistify.Spotify.API.MockClient, self(), fn ->
        pid = assert_in_registry({:spotify, user_id}, fail_on_timeout: false)
        if is_nil(pid), do: self(), else: pid
      end)

      # Ensure there is no existing token process
      refute_in_registry({:spotify, user_id})

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> put_session(:auth_provider, "spotify")
        |> put_session(:user_id, user_id)
        |> put_session(:refresh_token, encrypted_token)
        |> RestoreSpotifyToken.call([])

      # Should not halt the connection
      refute conn.halted
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "session has expired"

      # Session should be cleared
      assert get_session(conn, :user_id) == nil
      assert get_session(conn, :refresh_token) == nil

      # After a refresh failure, the session should not exist
      assert {:error, :not_found} = SessionManager.get_session(user_id)
    end
  end
end
