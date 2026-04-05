defmodule SetlistifyWeb.Auth.LiveHooksTest do
  use SetlistifyWeb.ConnCase, async: false

  alias Setlistify.Spotify.{SessionManager, UserSession}
  alias SetlistifyWeb.Auth.LiveHooks

  describe "on_mount: default" do
    test "assigns user data when authenticated" do
      # Start the registry
      Registry.start_link(keys: :unique, name: Setlistify.Spotify.UserSessionRegistry)

      start_supervised!(
        {DynamicSupervisor, strategy: :one_for_one, name: Setlistify.Spotify.SessionSupervisor}
      )

      user_id = "user-123"

      user_session = %UserSession{
        user_id: user_id,
        username: "Test User",
        access_token: "access-token-123",
        refresh_token: "test-refresh-token-123",
        expires_at: System.system_time(:second) + 3600
      }

      # Start the session manager
      {:ok, _pid} = SessionManager.start_link({user_id, user_session})

      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}},
        private: %{
          connect_info: %{request_path: "/test-path"},
          live_temp: %{flash: %{}}
        }
      }

      session = %{"user_id" => user_id, "auth_provider" => "spotify"}

      {:cont, updated_socket} = LiveHooks.on_mount(:default, %{}, session, socket)

      assert updated_socket.assigns.user_id == user_id
      assert updated_socket.assigns.user_session == user_session
    end

    test "assigns nil when not authenticated" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}},
        private: %{
          connect_info: %{request_path: "/test-path"},
          live_temp: %{flash: %{}}
        }
      }

      session = %{}

      {:cont, updated_socket} = LiveHooks.on_mount(:default, %{}, session, socket)

      assert updated_socket.assigns.user_id == nil
      assert updated_socket.assigns.user_session == nil
    end

    test "assigns nil when auth_provider is unknown" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}},
        private: %{
          connect_info: %{request_path: "/test-path"},
          live_temp: %{flash: %{}}
        }
      }

      session = %{"user_id" => "user-123", "auth_provider" => "unknown_provider"}

      {:cont, updated_socket} = LiveHooks.on_mount(:default, %{}, session, socket)

      assert updated_socket.assigns.user_id == nil
      assert updated_socket.assigns.user_session == nil
    end
  end

  describe "on_mount: ensure_authenticated" do
    test "redirects if user is not authenticated" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}},
        private: %{
          connect_info: %{request_path: "/test-path"},
          live_temp: %{flash: %{}}
        }
      }

      session = %{}

      {:halt, updated_socket} = LiveHooks.on_mount(:ensure_authenticated, %{}, session, socket)

      assert {:live, :redirect, %{kind: :push, to: "/?redirect_to=/test-path"}} =
               updated_socket.redirected
    end

    test "redirects if user session is not found" do
      # Start the registry
      Registry.start_link(keys: :unique, name: Setlistify.Spotify.UserSessionRegistry)

      user_id = "non-existent-user"

      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}},
        private: %{
          connect_info: %{request_path: "/test-path"},
          live_temp: %{flash: %{}}
        }
      }

      session = %{"user_id" => user_id}

      {:halt, updated_socket} = LiveHooks.on_mount(:ensure_authenticated, %{}, session, socket)

      assert {:live, :redirect, %{kind: :push, to: "/?redirect_to=/test-path"}} =
               updated_socket.redirected
    end

    test "allows authenticated users to continue" do
      # Start the registry
      Registry.start_link(keys: :unique, name: Setlistify.Spotify.UserSessionRegistry)

      start_supervised!(
        {DynamicSupervisor, strategy: :one_for_one, name: Setlistify.Spotify.SessionSupervisor}
      )

      user_id = "user-123"

      user_session = %UserSession{
        user_id: user_id,
        username: "Test User",
        access_token: "access-token-123",
        refresh_token: "test-refresh-token-123",
        expires_at: System.system_time(:second) + 3600
      }

      # Start the session manager
      {:ok, _pid} = SessionManager.start_link({user_id, user_session})

      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}},
        private: %{
          connect_info: %{request_path: "/test-path"},
          live_temp: %{flash: %{}}
        }
      }

      session = %{"user_id" => user_id, "auth_provider" => "spotify"}

      {:cont, updated_socket} = LiveHooks.on_mount(:ensure_authenticated, %{}, session, socket)

      assert updated_socket.assigns.user_id == user_id
      assert updated_socket.assigns.user_session == user_session
    end
  end
end
