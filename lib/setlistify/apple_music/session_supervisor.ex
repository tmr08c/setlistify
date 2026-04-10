defmodule Setlistify.AppleMusic.SessionSupervisor do
  @moduledoc """
  Supervisor for managing Apple Music user token processes.
  """

  alias Setlistify.AppleMusic.SessionManager
  alias Setlistify.AppleMusic.UserSession

  require Logger
  require OpenTelemetry.Tracer

  def start_user_token(user_id, %UserSession{} = session) do
    OpenTelemetry.Tracer.with_span "Setlistify.AppleMusic.SessionSupervisor.start_user_token" do
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
          Logger.info("Apple Music user token process started", %{
            user_id: user_id,
            pid: inspect(pid)
          })

          OpenTelemetry.Tracer.set_attributes([
            {"supervisor.child.pid", inspect(pid)},
            {"supervisor.child.started", true}
          ])

          OpenTelemetry.Tracer.set_status(:ok, "")
          result

        {:error, {:already_started, pid}} ->
          Logger.info("Apple Music user token process already running", %{
            user_id: user_id,
            pid: inspect(pid)
          })

          OpenTelemetry.Tracer.set_status(:ok, "")
          {:ok, pid}

        {:error, reason} = error ->
          Logger.error("Failed to start Apple Music user token process", %{
            user_id: user_id,
            error: reason
          })

          OpenTelemetry.Tracer.set_status(:error, "Failed to start child: #{inspect(reason)}")
          error
      end
    end
  end

  def stop_user_token(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.AppleMusic.SessionSupervisor.stop_user_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"supervisor.operation", "terminate_child"}
      ])

      case SessionManager.lookup(user_id) do
        {:ok, pid} ->
          case DynamicSupervisor.terminate_child(Setlistify.UserSessionSupervisor, pid) do
            :ok ->
              Logger.info("Apple Music user token process terminated", %{
                user_id: user_id,
                pid: inspect(pid)
              })

              OpenTelemetry.Tracer.set_attributes([
                {"supervisor.child.pid", inspect(pid)},
                {"supervisor.child.terminated", true}
              ])

              OpenTelemetry.Tracer.set_status(:ok, "")
              :ok

            {:error, reason} = error ->
              Logger.error("Failed to terminate Apple Music user token process", %{
                user_id: user_id,
                error: reason
              })

              OpenTelemetry.Tracer.set_status(
                :error,
                "Failed to terminate child: #{inspect(reason)}"
              )

              error
          end

        :error ->
          OpenTelemetry.Tracer.set_status(:error, "Process not found in registry")
          {:error, :not_found}
      end
    end
  end

  def get_session(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.AppleMusic.SessionSupervisor.get_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"supervisor.operation", "delegate_get_session"}
      ])

      result = SessionManager.get_session(user_id)

      case result do
        {:ok, _session} -> OpenTelemetry.Tracer.set_status(:ok, "")
        {:error, reason} -> OpenTelemetry.Tracer.set_status(:error, inspect(reason))
      end

      result
    end
  end
end
