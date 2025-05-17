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

  use GenServer
  require Logger
  alias Setlistify.Spotify.API
  alias Setlistify.Spotify.UserSession

  # TODO: this name may not be the most clear for the goal. Does `  @refresh_buffer` make it more clear?
  # Refresh token 5 minutes before expiration
  @refresh_threshold 5 * 60

  # Client API

  def start_link({user_id, initial_tokens_or_session}) do
    name = via_tuple(user_id)
    GenServer.start_link(__MODULE__, {user_id, initial_tokens_or_session}, name: name)
  end

  def get_token(user_id) do
    case lookup(user_id) do
      {:ok, pid} ->
        GenServer.call(pid, :get_token)

      :error ->
        {:error, :not_found}
    end
  end

  @deprecated "Use refresh_session/1 instead"
  def refresh_token(user_id) do
    case lookup(user_id) do
      {:ok, pid} -> GenServer.call(pid, :refresh_token)
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Refreshes the token for a specific user and returns the updated UserSession.
  """
  @spec refresh_session(binary()) :: {:ok, UserSession.t()} | {:error, atom()}
  def refresh_session(user_id) do
    case lookup(user_id) do
      {:ok, pid} -> GenServer.call(pid, :refresh_session)
      :error -> {:error, :not_found}
    end
  end

  def get_session(user_id) do
    case lookup(user_id) do
      {:ok, pid} -> GenServer.call(pid, :get_session)
      :error -> {:error, :not_found}
    end
  end

  def stop(user_id) do
    case lookup(user_id) do
      {:ok, pid} ->
        GenServer.stop(pid, :normal)

      :error ->
        {:error, :not_found}
    end
  end

  # Server Callbacks

  @impl true
  def init({user_id, initial_data}) do
    state =
      case initial_data do
        %UserSession{} = session ->
          # UserSession already has expires_at
          schedule_refresh(session.expires_at - timestamp() - @refresh_threshold)

          Map.from_struct(session)
          |> Map.put(:user_id, user_id)

        # TODO this should be removed when we have fully migrated to UserSession
        %{access_token: _, refresh_token: _, expires_in: expires_in} = tokens ->
          # Legacy token map format - convert to proper state
          schedule_refresh(expires_in - @refresh_threshold)

          tokens
          |> Map.put(:expires_at, timestamp() + expires_in)
          |> Map.put(:user_id, user_id)
      end

    {:ok, state}
  end

  @impl true
  def handle_call(:get_token, _from, %{access_token: token} = state) do
    {:reply, {:ok, token}, state}
  end

  @impl true
  def handle_call(:get_session, _from, state) do
    # Convert state back to UserSession struct
    session = %UserSession{
      access_token: state.access_token,
      refresh_token: state.refresh_token,
      expires_at: state.expires_at,
      user_id: state.user_id,
      username: Map.get(state, :username, state.user_id)
    }

    {:reply, {:ok, session}, state}
  end

  @impl true
  def handle_call(:refresh_token, _from, state) do
    case do_refresh_token(state) do
      {:ok, new_state, new_tokens} ->
        {:reply, {:ok, new_tokens.access_token}, new_state}

      {:error, _reason} = error ->
        {:stop, :normal, error, state}
    end
  end

  @impl true
  def handle_call(:refresh_session, _from, state) do
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

        {:reply, {:ok, session}, new_state}

      {:error, _reason} = error ->
        {:stop, :normal, error, state}
    end
  end

  @impl true
  def handle_info(:refresh_token, state) do
    case do_refresh_token(state) do
      {:ok, new_state, _new_tokens} ->
        {:noreply, new_state}

      {:error, _reason} ->
        {:stop, :normal, state}
    end
  end

  # Helper functions

  defp via_tuple(user_id) do
    {:via, Registry, {Setlistify.UserSessionRegistry, user_id}}
  end

  @doc """
  Looks up a token manager process by user ID.
  Returns {:ok, pid} if found, :error otherwise.
  """
  def lookup(user_id) do
    case Registry.lookup(Setlistify.UserSessionRegistry, user_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  defp schedule_refresh(after_seconds) when after_seconds > 0 do
    Process.send_after(self(), :refresh_token, :timer.seconds(after_seconds))
  end

  defp schedule_refresh(_), do: Process.send(self(), :refresh_token, [])

  defp timestamp, do: System.system_time(:second)

  defp do_refresh_token(%{refresh_token: refresh_token} = state) do
    case API.refresh_token(refresh_token) do
      {:ok, new_tokens} ->
        schedule_refresh(new_tokens.expires_in - @refresh_threshold)

        new_state =
          state
          |> Map.merge(new_tokens)
          |> Map.put(:expires_at, timestamp() + new_tokens.expires_in)

        # Broadcast token refresh event to interested LiveViews
        broadcast_token_refreshed(new_state)

        {:ok, new_state, new_tokens}

      {:error, _reason} = error ->
        error
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
