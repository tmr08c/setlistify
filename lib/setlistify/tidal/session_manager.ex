defmodule Setlistify.Tidal.SessionManager do
  @moduledoc """
  GenServer that manages a Tidal user session (tokens + region) for the
  duration of a user's session.

  Mirrors `Setlistify.Spotify.SessionManager` (OAuth with a refresh timer), with
  two Tidal-specific differences:

    * **Short-lived access tokens.** Tidal access tokens last ~4 hours
      (`expires_in: 14400`), so the refresh timer fires at roughly the 3.5 hour
      mark rather than Spotify's ~55 minute mark.
    * **No refresh-token rotation.** Tidal's refresh response contains only a new
      `access_token`/`expires_in` — never a new `refresh_token`. The manager
      therefore preserves the existing refresh token across refreshes instead of
      reading it from the response.

  The session also carries `:country_code`, which is set once at sign-in and
  preserved untouched across refreshes (mirrors Apple Music's `:storefront`).
  """

  @behaviour Setlistify.UserSessionManager

  use GenServer

  alias Setlistify.SessionRegistry
  alias Setlistify.Tidal.API
  alias Setlistify.Tidal.UserSession

  require Logger
  require OpenTelemetry.Tracer

  # Tidal access tokens last ~4 hours; refresh ~30 minutes early (≈ 3.5 h mark).
  @refresh_buffer 30 * 60

  # Client API

  @impl Setlistify.UserSessionManager
  def start_link({user_id, %UserSession{} = session}) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionManager.start_link" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"session.operation", "start"}
      ])

      name = SessionRegistry.via_tuple(:tidal, user_id)

      case GenServer.start_link(__MODULE__, {user_id, session}, name: name) do
        {:ok, pid} = result ->
          Logger.info("Tidal session manager started", %{user_id: user_id, pid: inspect(pid)})
          result

        {:error, reason} = error ->
          Logger.error("Failed to start Tidal session manager", %{user_id: user_id, error: reason})

          OpenTelemetry.Tracer.set_status(
            :error,
            "Failed to start session manager: #{inspect(reason)}"
          )

          error
      end
    end
  end

  def get_token(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionManager.get_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"session.operation", "get_token"}
      ])

      case SessionRegistry.lookup(:tidal, user_id) do
        {:ok, pid} ->
          result = GenServer.call(pid, :get_token)

          case result do
            {:ok, _token} ->
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
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionManager.refresh_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"session.operation", "refresh"}
      ])

      case SessionRegistry.lookup(:tidal, user_id) do
        {:ok, pid} ->
          result = GenServer.call(pid, :refresh_session)

          case result do
            {:ok, _session} ->
              Logger.info("Tidal session refreshed", %{user_id: user_id})
              OpenTelemetry.Tracer.set_attribute("session.refreshed", true)
              result

            {:error, reason} ->
              Logger.error("Tidal session refresh failed", %{user_id: user_id, error: reason})
              OpenTelemetry.Tracer.set_status(:error, "Session refresh failed: #{inspect(reason)}")
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
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionManager.get_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"session.operation", "get"}
      ])

      case SessionRegistry.lookup(:tidal, user_id) do
        {:ok, pid} ->
          result = GenServer.call(pid, :get_session)

          case result do
            {:ok, _session} ->
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
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionManager.stop" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"session.operation", "stop"}
      ])

      case SessionRegistry.lookup(:tidal, user_id) do
        {:ok, pid} ->
          result = GenServer.stop(pid, :normal)
          Logger.info("Tidal session manager stopped", %{user_id: user_id})
          result

        :error ->
          OpenTelemetry.Tracer.set_status(:error, "Session not found")
          {:error, :not_found}
      end
    end
  end

  @doc """
  Looks up a session manager process by user ID.
  Returns `{:ok, pid}` if found, `:error` otherwise.
  """
  def lookup(user_id), do: SessionRegistry.lookup(:tidal, user_id)

  # Server Callbacks

  @impl true
  def init({user_id, %UserSession{} = session}) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionManager.init" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"genserver.operation", "init"}
      ])

      # Use the passed user_id to ensure consistency with the Registry key.
      state = Map.put(session, :user_id, user_id)
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
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionManager.handle_call.get_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", state.user_id},
        {"enduser.id", state.user_id},
        {"genserver.operation", "handle_call"},
        {"genserver.message", "get_token"}
      ])

      {:reply, {:ok, token}, state}
    end
  end

  @impl true
  def handle_call(:get_session, _from, state) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionManager.handle_call.get_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", state.user_id},
        {"enduser.id", state.user_id},
        {"genserver.operation", "handle_call"},
        {"genserver.message", "get_session"}
      ])

      {:reply, {:ok, to_user_session(state)}, state}
    end
  end

  @impl true
  def handle_call(:refresh_session, _from, state) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionManager.handle_call.refresh_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", state.user_id},
        {"enduser.id", state.user_id},
        {"genserver.operation", "handle_call"},
        {"genserver.message", "refresh_session"}
      ])

      case do_refresh_token(state) do
        {:ok, new_state} ->
          {:reply, {:ok, to_user_session(new_state)}, new_state}

        {:error, reason} = error ->
          OpenTelemetry.Tracer.set_status(:error, "Token refresh failed: #{inspect(reason)}")
          {:stop, :normal, error, state}
      end
    end
  end

  @impl true
  def handle_info(:refresh_token, state) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionManager.handle_info.refresh_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", state.user_id},
        {"enduser.id", state.user_id},
        {"genserver.operation", "handle_info"},
        {"genserver.message", "refresh_token"},
        {"session.scheduled_refresh", true}
      ])

      case do_refresh_token(state) do
        {:ok, new_state} ->
          {:noreply, new_state}

        {:error, reason} ->
          Logger.error("Scheduled Tidal token refresh failed", %{user_id: state.user_id, error: reason})
          OpenTelemetry.Tracer.set_status(:error, "Scheduled refresh failed: #{inspect(reason)}")
          {:stop, :normal, state}
      end
    end
  end

  # Helper functions

  defp schedule_refresh(after_seconds) when after_seconds > 0 do
    Process.send_after(self(), :refresh_token, to_timeout(second: after_seconds))
  end

  defp schedule_refresh(_), do: Process.send(self(), :refresh_token, [])

  defp timestamp, do: System.system_time(:second)

  defp do_refresh_token(%{refresh_token: refresh_token} = state) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionManager.do_refresh_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", state.user_id},
        {"enduser.id", state.user_id},
        {"session.operation", "token_refresh"}
      ])

      case API.refresh_token(refresh_token) do
        {:ok, new_tokens} ->
          schedule_refresh(new_tokens.expires_in - @refresh_buffer)

          # Tidal does NOT rotate refresh tokens — preserve the existing one and
          # update only the access token and expiry. :country_code is untouched.
          new_state =
            state
            |> Map.put(:access_token, new_tokens.access_token)
            |> Map.put(:expires_at, timestamp() + new_tokens.expires_in)

          Phoenix.PubSub.broadcast(
            Setlistify.PubSub,
            "user:#{new_state.user_id}",
            {:token_refreshed, to_user_session(new_state)}
          )

          OpenTelemetry.Tracer.set_attributes([
            {"session.token.expires_in", new_tokens.expires_in},
            {"session.token.refreshed", true}
          ])

          OpenTelemetry.Tracer.add_event("token_refreshed", %{
            "user.id" => state.user_id,
            "expires_in" => new_tokens.expires_in
          })

          {:ok, new_state}

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

  defp to_user_session(state) do
    %UserSession{
      access_token: state.access_token,
      refresh_token: state.refresh_token,
      expires_at: state.expires_at,
      user_id: state.user_id,
      country_code: state.country_code
    }
  end
end
