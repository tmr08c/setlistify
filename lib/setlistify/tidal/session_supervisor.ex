defmodule Setlistify.Tidal.SessionSupervisor do
  @moduledoc """
  Supervisor helpers for managing Tidal user session processes.

  A thin wrapper over the shared `Setlistify.UserSessionSupervisor`
  `DynamicSupervisor`, mirroring `Setlistify.Spotify.SessionSupervisor`.
  """

  alias Setlistify.Tidal.SessionManager

  require Logger
  require OpenTelemetry.Tracer

  def start_user_token(user_id, %Setlistify.Tidal.UserSession{} = session) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionSupervisor.start_user_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"supervisor.operation", "start_child"}
      ])

      case DynamicSupervisor.start_child(
             Setlistify.UserSessionSupervisor,
             {SessionManager, {user_id, session}}
           ) do
        {:ok, pid} = result ->
          Logger.info("Tidal session process started", %{user_id: user_id, pid: inspect(pid)})

          OpenTelemetry.Tracer.set_attributes([
            {"supervisor.child.pid", inspect(pid)},
            {"supervisor.child.started", true}
          ])

          result

        {:ok, pid, _info} = result ->
          Logger.info("Tidal session process started with info", %{
            user_id: user_id,
            pid: inspect(pid)
          })

          OpenTelemetry.Tracer.set_attributes([
            {"supervisor.child.pid", inspect(pid)},
            {"supervisor.child.started", true}
          ])

          result

        {:error, {:already_started, pid}} ->
          Logger.info("Tidal session process already running", %{
            user_id: user_id,
            pid: inspect(pid)
          })

          {:ok, pid}

        {:error, reason} = error ->
          Logger.error("Failed to start Tidal session process", %{user_id: user_id, error: reason})
          OpenTelemetry.Tracer.set_status(:error, "Failed to start child: #{inspect(reason)}")
          error
      end
    end
  end

  def stop_user_token(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionSupervisor.stop_user_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"supervisor.operation", "terminate_child"}
      ])

      case SessionManager.lookup(user_id) do
        {:ok, pid} ->
          case DynamicSupervisor.terminate_child(Setlistify.UserSessionSupervisor, pid) do
            :ok ->
              Logger.info("Tidal session process terminated", %{user_id: user_id, pid: inspect(pid)})

              OpenTelemetry.Tracer.set_attributes([
                {"supervisor.child.pid", inspect(pid)},
                {"supervisor.child.terminated", true}
              ])

              :ok

            {:error, reason} = error ->
              Logger.error("Failed to terminate Tidal session process", %{
                user_id: user_id,
                error: reason
              })

              OpenTelemetry.Tracer.set_status(:error, "Failed to terminate child: #{inspect(reason)}")
              error
          end

        :error ->
          OpenTelemetry.Tracer.set_status(:error, "Process not found in registry")
          {:error, :not_found}
      end
    end
  end

  def get_token(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionSupervisor.get_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"supervisor.operation", "delegate_get_token"}
      ])

      result = SessionManager.get_token(user_id)

      case result do
        {:ok, _token} ->
          :ok

        {:error, reason} ->
          OpenTelemetry.Tracer.set_status(:error, "Failed to get token: #{inspect(reason)}")
      end

      result
    end
  end

  def refresh_session(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.Tidal.SessionSupervisor.refresh_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"supervisor.operation", "delegate_refresh_session"}
      ])

      result = SessionManager.refresh_session(user_id)

      case result do
        {:ok, _session} ->
          :ok

        {:error, reason} ->
          OpenTelemetry.Tracer.set_status(:error, "Failed to refresh session: #{inspect(reason)}")
      end

      result
    end
  end
end
