defmodule Setlistify.Spotify.SessionManager do
  @moduledoc """
  GenServer that manages Spotify user sessions including tokens and user data.

  The SessionManager is responsible for:
  - Storing and managing UserSession data (tokens, user info)
  - Automatically refreshing tokens before they expire
  - Broadcasting token refresh events via PubSub
  - Providing a centralized access point for session data

  ## Architecture Diagram

  ```mermaid
  graph TB
    subgraph "Session Management"
      SS[SessionSupervisor]
      SM1[SessionManager<br/>User 1]
      SM2[SessionManager<br/>User 2]
      SM3[SessionManager<br/>User N]
      REG[(UserSessionRegistry)]
    end

    subgraph "Web Layer"
      LV1[LiveView 1]
      LV2[LiveView 2]
      CTRL[Controllers]
    end

    subgraph "External"
      SPOT[Spotify API]
    end

    SS -->|supervises| SM1
    SS -->|supervises| SM2
    SS -->|supervises| SM3

    SM1 -->|registers| REG
    SM2 -->|registers| REG
    SM3 -->|registers| REG

    LV1 -->|get_session| SM1
    LV2 -->|get_session| SM2
    CTRL -->|get_session| SM1

    SM1 -->|refresh_token| SPOT
    SM1 -->|broadcasts| PubSub

    PubSub -.->|token_refreshed| LV1
    PubSub -.->|token_refreshed| LV2
  ```

  ## Token Refresh Flow

  ```mermaid
  sequenceDiagram
    participant SM as SessionManager
    participant Timer
    participant API as Spotify API
    participant PS as PubSub
    participant LV as LiveView

    Note over SM: Token expires in 60 min
    SM->>Timer: Schedule refresh<br/>(55 min)
    Note over SM: Wait...
    Timer-->>SM: :refresh_token message
    SM->>API: POST /api/token<br/>(refresh_token)
    API-->>SM: New tokens
    SM->>SM: Update state
    SM->>Timer: Schedule next refresh
    SM->>PS: broadcast(:token_refreshed)
    PS-->>LV: {:token_refreshed, session}
    LV->>LV: Update socket assigns
  ```

  ## Usage Example

  ```elixir
  # Start a new session
  {:ok, pid} = SessionManager.start_link({user_id, user_session})

  # Get current session data
  {:ok, session} = SessionManager.get_session(user_id)

  # Manually refresh (usually automatic)
  {:ok, new_session} = SessionManager.refresh_session(user_id)
  ```
  """

  @behaviour Setlistify.UserSessionManager

  use GenServer

  alias Setlistify.SessionRegistry
  alias Setlistify.Spotify.API
  alias Setlistify.Spotify.UserSession

  require Logger
  require OpenTelemetry.Tracer

  # Refresh token 5 minutes before expiration
  @refresh_buffer 5 * 60

  # Client API

  @impl Setlistify.UserSessionManager
  def start_link({user_id, initial_tokens_or_session}) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.SessionManager.start_link" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"session.operation", "start"}
      ])

      name = SessionRegistry.via_tuple(:spotify, user_id)

      case GenServer.start_link(__MODULE__, {user_id, initial_tokens_or_session}, name: name) do
        {:ok, pid} = result ->
          Logger.info("Session manager started", %{user_id: user_id, pid: inspect(pid)})
          OpenTelemetry.Tracer.set_status(:ok, "")
          result

        {:error, reason} = error ->
          Logger.error("Failed to start session manager", %{user_id: user_id, error: reason})

          OpenTelemetry.Tracer.set_status(
            :error,
            "Failed to start session manager: #{inspect(reason)}"
          )

          error
      end
    end
  end

  def get_token(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.SessionManager.get_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"session.operation", "get_token"}
      ])

      case SessionRegistry.lookup(:spotify, user_id) do
        {:ok, pid} ->
          result = GenServer.call(pid, :get_token)

          case result do
            {:ok, _token} ->
              OpenTelemetry.Tracer.set_status(:ok, "")
              result

            {:error, reason} ->
              OpenTelemetry.Tracer.set_status(:error, "Failed to get token: #{inspect(reason)}")
              result
          end

        :error ->
          OpenTelemetry.Tracer.set_status(:error, "Session not found")
          {:error, :not_found}
      end
    end
  end

  @doc """
  Refreshes the token for a specific user and returns the updated UserSession.
  """
  @spec refresh_session(binary()) :: {:ok, UserSession.t()} | {:error, atom()}
  def refresh_session(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.SessionManager.refresh_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"session.operation", "refresh"}
      ])

      case SessionRegistry.lookup(:spotify, user_id) do
        {:ok, pid} ->
          result = GenServer.call(pid, :refresh_session)

          case result do
            {:ok, _session} ->
              Logger.info("Session refreshed", %{user_id: user_id})
              OpenTelemetry.Tracer.set_status(:ok, "")
              OpenTelemetry.Tracer.set_attribute("session.refreshed", true)
              result

            {:error, reason} ->
              Logger.error("Session refresh failed", %{user_id: user_id, error: reason})

              OpenTelemetry.Tracer.set_status(
                :error,
                "Session refresh failed: #{inspect(reason)}"
              )

              result
          end

        :error ->
          OpenTelemetry.Tracer.set_status(:error, "Session not found")
          {:error, :not_found}
      end
    end
  end

  @impl Setlistify.UserSessionManager
  def get_session(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.SessionManager.get_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"session.operation", "get"}
      ])

      case SessionRegistry.lookup(:spotify, user_id) do
        {:ok, pid} ->
          result = GenServer.call(pid, :get_session)

          case result do
            {:ok, _session} ->
              OpenTelemetry.Tracer.set_status(:ok, "")
              result

            {:error, reason} ->
              OpenTelemetry.Tracer.set_status(:error, "Failed to get session: #{inspect(reason)}")
              result
          end

        :error ->
          OpenTelemetry.Tracer.set_status(:error, "Session not found")
          {:error, :not_found}
      end
    end
  end

  @impl Setlistify.UserSessionManager
  def stop(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.SessionManager.stop" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"session.operation", "stop"}
      ])

      case SessionRegistry.lookup(:spotify, user_id) do
        {:ok, pid} ->
          result = GenServer.stop(pid, :normal)
          Logger.info("Session manager stopped", %{user_id: user_id})
          OpenTelemetry.Tracer.set_status(:ok, "")
          result

        :error ->
          OpenTelemetry.Tracer.set_status(:error, "Session not found")
          {:error, :not_found}
      end
    end
  end

  # Server Callbacks

  @impl true
  def init({user_id, %UserSession{} = session}) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.SessionManager.init" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"genserver.operation", "init"}
      ])

      # Use the passed user_id to ensure consistency with Registry key
      state = Map.put(session, :user_id, user_id)
      OpenTelemetry.Tracer.set_status(:ok, "")
      {:ok, state, {:continue, :schedule_refresh}}
    end
  end

  @impl true
  def handle_continue(:schedule_refresh, %{expires_at: expires_at} = state) do
    schedule_refresh(expires_at - timestamp() - @refresh_buffer)

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_token, _from, %{access_token: token} = state) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.SessionManager.handle_call.get_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", state.user_id},
        {"enduser.id", state.user_id},
        {"genserver.operation", "handle_call"},
        {"genserver.message", "get_token"}
      ])

      OpenTelemetry.Tracer.set_status(:ok, "")
      {:reply, {:ok, token}, state}
    end
  end

  @impl true
  def handle_call(:get_session, _from, state) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.SessionManager.handle_call.get_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", state.user_id},
        {"enduser.id", state.user_id},
        {"genserver.operation", "handle_call"},
        {"genserver.message", "get_session"}
      ])

      # Convert state back to UserSession struct
      session = %UserSession{
        access_token: state.access_token,
        refresh_token: state.refresh_token,
        expires_at: state.expires_at,
        user_id: state.user_id,
        username: Map.get(state, :username, state.user_id)
      }

      OpenTelemetry.Tracer.set_status(:ok, "")
      {:reply, {:ok, session}, state}
    end
  end

  @impl true
  def handle_call(:refresh_session, _from, state) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.SessionManager.handle_call.refresh_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", state.user_id},
        {"enduser.id", state.user_id},
        {"genserver.operation", "handle_call"},
        {"genserver.message", "refresh_session"}
      ])

      case do_refresh_token(state) do
        {:ok, new_state, _new_tokens} ->
          # Return the full UserSession
          session = %UserSession{
            access_token: new_state.access_token,
            refresh_token: new_state.refresh_token,
            expires_at: new_state.expires_at,
            user_id: new_state.user_id,
            username: Map.get(new_state, :username, new_state.user_id)
          }

          OpenTelemetry.Tracer.set_status(:ok, "")
          {:reply, {:ok, session}, new_state}

        {:error, reason} = error ->
          OpenTelemetry.Tracer.set_status(:error, "Token refresh failed: #{inspect(reason)}")
          {:stop, :normal, error, state}
      end
    end
  end

  @impl true
  def handle_info(:refresh_token, state) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.SessionManager.handle_info.refresh_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", state.user_id},
        {"enduser.id", state.user_id},
        {"genserver.operation", "handle_info"},
        {"genserver.message", "refresh_token"},
        {"session.scheduled_refresh", true}
      ])

      case do_refresh_token(state) do
        {:ok, new_state, _new_tokens} ->
          OpenTelemetry.Tracer.set_status(:ok, "")
          {:noreply, new_state}

        {:error, reason} ->
          Logger.error("Scheduled token refresh failed", %{user_id: state.user_id, error: reason})
          OpenTelemetry.Tracer.set_status(:error, "Scheduled refresh failed: #{inspect(reason)}")
          {:stop, :normal, state}
      end
    end
  end

  # Helper functions

  @doc """
  Looks up a token manager process by user ID.
  Returns {:ok, pid} if found, :error otherwise.
  """
  def lookup(user_id), do: SessionRegistry.lookup(:spotify, user_id)

  defp schedule_refresh(after_seconds) when after_seconds > 0 do
    Process.send_after(self(), :refresh_token, to_timeout(second: after_seconds))
  end

  defp schedule_refresh(_), do: Process.send(self(), :refresh_token, [])

  defp timestamp, do: System.system_time(:second)

  defp do_refresh_token(%{refresh_token: refresh_token} = state) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.SessionManager.do_refresh_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", state.user_id},
        {"enduser.id", state.user_id},
        {"session.operation", "token_refresh"}
      ])

      case API.refresh_token(refresh_token) do
        {:ok, new_tokens} ->
          schedule_refresh(new_tokens.expires_in - @refresh_buffer)

          new_state =
            state
            |> Map.merge(new_tokens)
            |> Map.put(:expires_at, timestamp() + new_tokens.expires_in)

          # Broadcast token refresh event to interested LiveViews
          broadcast_token_refreshed(new_state)

          OpenTelemetry.Tracer.set_attributes([
            {"session.token.expires_in", new_tokens.expires_in},
            {"session.token.refreshed", true}
          ])

          OpenTelemetry.Tracer.add_event("token_refreshed", %{
            "user.id" => state.user_id,
            "expires_in" => new_tokens.expires_in
          })

          OpenTelemetry.Tracer.set_status(:ok, "")

          {:ok, new_state, new_tokens}

        {:error, reason} = error ->
          OpenTelemetry.Tracer.set_status(:error, "Token refresh failed: #{inspect(reason)}")

          OpenTelemetry.Tracer.add_event("token_refresh_failed", %{
            "user.id" => state.user_id,
            "error" => inspect(reason)
          })

          error
      end
    end
  end

  defp broadcast_token_refreshed(state) do
    user_session = %UserSession{
      access_token: state.access_token,
      refresh_token: state.refresh_token,
      expires_at: state.expires_at,
      user_id: state.user_id,
      username: Map.get(state, :username, state.user_id)
    }

    Phoenix.PubSub.broadcast(
      Setlistify.PubSub,
      "user:#{state.user_id}",
      {:token_refreshed, user_session}
    )
  end
end
