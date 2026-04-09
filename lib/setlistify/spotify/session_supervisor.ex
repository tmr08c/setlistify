defmodule Setlistify.Spotify.SessionSupervisor do
  @moduledoc """
  Supervisor for managing Spotify user token processes.
  """

  require Logger
  require OpenTelemetry.Tracer
  alias Setlistify.Spotify.SessionManager

  def start_user_token(user_id, tokens_or_session) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.SessionSupervisor.start_user_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"supervisor.operation", "start_child"}
      ])

      case DynamicSupervisor.start_child(
             Setlistify.UserSessionSupervisor,
             {SessionManager, {user_id, tokens_or_session}}
           ) do
        {:ok, pid} = result ->
          Logger.info("User token process started", %{user_id: user_id, pid: inspect(pid)})

          OpenTelemetry.Tracer.set_attributes([
            {"supervisor.child.pid", inspect(pid)},
            {"supervisor.child.started", true}
          ])

          OpenTelemetry.Tracer.set_status(:ok, "")
          result

        {:ok, pid, _info} = result ->
          Logger.info("User token process started with info", %{
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
          Logger.info("User token process already running", %{
            user_id: user_id,
            pid: inspect(pid)
          })

          OpenTelemetry.Tracer.set_status(:ok, "")
          {:ok, pid}

        {:error, reason} = error ->
          Logger.error("Failed to start user token process", %{user_id: user_id, error: reason})
          OpenTelemetry.Tracer.set_status(:error, "Failed to start child: #{inspect(reason)}")
          error
      end
    end
  end

  def stop_user_token(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.SessionSupervisor.stop_user_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"supervisor.operation", "terminate_child"}
      ])

      # Find the pid using the registry and terminate the child
      case SessionManager.lookup(user_id) do
        {:ok, pid} ->
          # Use DynamicSupervisor.terminate_child to remove it from supervision
          # This will return :ok on success or {:error, :not_found} if the process isn't found
          case DynamicSupervisor.terminate_child(Setlistify.UserSessionSupervisor, pid) do
            :ok ->
              Logger.info("User token process terminated", %{user_id: user_id, pid: inspect(pid)})

              OpenTelemetry.Tracer.set_attributes([
                {"supervisor.child.pid", inspect(pid)},
                {"supervisor.child.terminated", true}
              ])

              OpenTelemetry.Tracer.set_status(:ok, "")
              :ok

            {:error, reason} = error ->
              Logger.error("Failed to terminate user token process", %{
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
          # No process found in the registry, just return the same error as DynamicSupervisor would
          OpenTelemetry.Tracer.set_status(:error, "Process not found in registry")
          {:error, :not_found}
      end
    end
  end

  def get_token(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.SessionSupervisor.get_token" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"supervisor.operation", "delegate_get_token"}
      ])

      result = SessionManager.get_token(user_id)

      case result do
        {:ok, _token} ->
          OpenTelemetry.Tracer.set_status(:ok, "")

        {:error, reason} ->
          OpenTelemetry.Tracer.set_status(:error, "Failed to get token: #{inspect(reason)}")
      end

      result
    end
  end

  def refresh_session(user_id) do
    OpenTelemetry.Tracer.with_span "Setlistify.Spotify.SessionSupervisor.refresh_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"enduser.id", user_id},
        {"supervisor.operation", "delegate_refresh_session"}
      ])

      result = SessionManager.refresh_session(user_id)

      case result do
        {:ok, _session} ->
          OpenTelemetry.Tracer.set_status(:ok, "")

        {:error, reason} ->
          OpenTelemetry.Tracer.set_status(:error, "Failed to refresh session: #{inspect(reason)}")
      end

      result
    end
  end
end
