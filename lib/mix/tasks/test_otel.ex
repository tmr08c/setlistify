defmodule Mix.Tasks.TestOtel do
  @moduledoc """
  Mix task to test OpenTelemetry tracing functionality.

  This task starts the application and sends test traces to verify
  that the observability stack is working correctly.

  ## Usage

      mix test_otel

  """

  use Mix.Task
  require Logger
  require OpenTelemetry.Tracer

  @shortdoc "Test OpenTelemetry tracing setup"

  def run(_args) do
    Logger.info("Starting OpenTelemetry test...")

    # Start the application to ensure all dependencies are running
    {:ok, _} = Application.ensure_all_started(:setlistify)

    # Wait a moment for everything to initialize
    Process.sleep(1000)

    # Debug: Check if OpenTelemetry services are running
    Logger.info("Checking OpenTelemetry application status...")

    otel_apps =
      Application.started_applications()
      |> Enum.filter(fn {app, _, _} ->
        String.contains?(to_string(app), "opentelemetry")
      end)

    Logger.info("OpenTelemetry applications: #{inspect(otel_apps)}")

    Logger.info("Testing basic OpenTelemetry span...")
    test_basic_span()

    Logger.info("Testing nested spans...")
    test_nested_spans()

    Logger.info("Testing exception handling...")
    test_exception_handling()

    if function_exported?(Setlistify.Observability, :test_trace, 0) do
      Logger.info("Testing application-specific observability...")
      Setlistify.Observability.test_trace()
    end

    Logger.info("Testing SessionManager tracing...")
    test_session_manager()

    # Wait longer for traces to be exported in batches
    Logger.info("Waiting for traces to be exported...")
    Process.sleep(5000)

    Logger.info("OpenTelemetry test completed! Check Grafana at http://localhost:3000")
    Logger.info("Look for traces in Tempo with service name 'setlistify'")
  end

  defp test_basic_span do
    OpenTelemetry.Tracer.with_span "test.basic_span" do
      OpenTelemetry.Tracer.set_attributes([
        {"test.type", "basic"},
        {"test.timestamp", System.system_time(:second)}
      ])

      Logger.info("Executing basic test span")
      Process.sleep(100)

      OpenTelemetry.Tracer.add_event("Basic span test event", %{
        "event.data" => "test data"
      })

      {:ok, "basic span completed"}
    end
  end

  defp test_nested_spans do
    OpenTelemetry.Tracer.with_span "test.parent_span" do
      OpenTelemetry.Tracer.set_attributes([{"test.type", "parent"}])
      Logger.info("In parent span")

      OpenTelemetry.Tracer.with_span "test.child_span" do
        OpenTelemetry.Tracer.set_attributes([{"test.type", "child"}])
        Logger.info("In child span")
        Process.sleep(50)

        OpenTelemetry.Tracer.with_span "test.grandchild_span" do
          OpenTelemetry.Tracer.set_attributes([{"test.type", "grandchild"}])
          Logger.info("In grandchild span")
          Process.sleep(25)
        end
      end

      {:ok, "nested spans completed"}
    end
  end

  defp test_exception_handling do
    try do
      OpenTelemetry.Tracer.with_span "test.exception_span" do
        OpenTelemetry.Tracer.set_attributes([{"test.type", "exception"}])
        Logger.info("About to raise an exception...")
        raise ArgumentError, "Test exception for OpenTelemetry"
      end
    rescue
      ArgumentError ->
        Logger.info("Exception caught as expected")
        :ok
    end
  end

  defp test_session_manager do
    # Test session manager functions if available
    try do
      # Create a fake user session for testing
      user_session = %Setlistify.Spotify.UserSession{
        access_token: "test_token",
        refresh_token: "test_refresh",
        expires_at: System.system_time(:second) + 3600,
        user_id: "test_user_123",
        username: "test_user"
      }

      # This will create spans for session operations
      OpenTelemetry.Tracer.with_span "test.session_operations" do
        OpenTelemetry.Tracer.set_attributes([
          {"test.type", "session_management"},
          {"user_id", "test_user_123"}
        ])

        Logger.info("Testing session manager instrumentation...")

        # Start a session manager process
        case Setlistify.Spotify.SessionSupervisor.start_user_token("test_user_123", user_session) do
          {:ok, _pid} ->
            Logger.info("Session manager started successfully")

            # Test getting session (which should create spans)
            case Setlistify.Spotify.SessionManager.get_session("test_user_123") do
              {:ok, _session} ->
                Logger.info("Session retrieved successfully")

              {:error, reason} ->
                Logger.warning("Failed to get session: #{inspect(reason)}")
            end

            # Clean up
            Setlistify.Spotify.SessionSupervisor.stop_user_token("test_user_123")

          {:error, {:already_started, _pid}} ->
            Logger.info("Session manager already running")

          {:error, reason} ->
            Logger.warning("Failed to start session manager: #{inspect(reason)}")
        end
      end
    rescue
      error ->
        Logger.error("Error testing session manager: #{inspect(error)}")
    end
  end
end
