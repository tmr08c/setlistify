defmodule Setlistify.AppleMusic.SessionManager do
  @moduledoc """
  GenServer that stores an Apple Music user session for the duration of a
  user's browser session.

  Apple Music user tokens are valid for approximately six months with no
  server-side refresh endpoint. This GenServer stores the session as-is —
  there is no refresh timer, no scheduled token rotation, and no PubSub
  broadcast on token change.
  """

  @behaviour Setlistify.UserSessionManager

  use GenServer

  alias Setlistify.AppleMusic.UserSession
  alias Setlistify.SessionRegistry

  require Logger
  require OpenTelemetry.Tracer

  @impl Setlistify.UserSessionManager
  def start_link({user_id, %UserSession{} = session}) do
    OpenTelemetry.Tracer.with_span "Setlistify.AppleMusic.SessionManager.start_link" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"session.operation", "start"}
      ])

      case GenServer.start_link(__MODULE__, session,
             name: SessionRegistry.via_tuple(:apple_music, user_id)
           ) do
        {:ok, pid} = result ->
          Logger.info("Apple Music session manager started", %{
            user_id: user_id,
            pid: inspect(pid)
          })

          OpenTelemetry.Tracer.set_status(:ok, "")
          result

        {:error, reason} = error ->
          Logger.error("Failed to start Apple Music session manager", %{
            user_id: user_id,
            error: reason
          })

          OpenTelemetry.Tracer.set_status(
            :error,
            "Failed to start session manager: #{inspect(reason)}"
          )

          error
      end
    end
  end

  @impl Setlistify.UserSessionManager
  def get_session(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.AppleMusic.SessionManager.get_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"session.operation", "get"}
      ])

      case SessionRegistry.lookup(:apple_music, user_id) do
        {:ok, pid} ->
          result = {:ok, GenServer.call(pid, :get_session)}
          OpenTelemetry.Tracer.set_status(:ok, "")
          result

        :error ->
          OpenTelemetry.Tracer.set_status(:error, "Session not found")
          {:error, :not_found}
      end
    end
  end

  @impl Setlistify.UserSessionManager
  def stop(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.AppleMusic.SessionManager.stop" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"session.operation", "stop"}
      ])

      case SessionRegistry.lookup(:apple_music, user_id) do
        {:ok, pid} ->
          GenServer.stop(pid, :normal)
          Logger.info("Apple Music session manager stopped", %{user_id: user_id})
          OpenTelemetry.Tracer.set_status(:ok, "")
          :ok

        :error ->
          OpenTelemetry.Tracer.set_status(:error, "Session not found")
          {:error, :not_found}
      end
    end
  end

  def lookup(user_id), do: SessionRegistry.lookup(:apple_music, user_id)

  @impl true
  def init(%UserSession{} = session), do: {:ok, session}

  @impl true
  def handle_call(:get_session, _from, session), do: {:reply, session, session}
end
