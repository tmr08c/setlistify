defmodule Setlistify.Observability do
  @moduledoc """
  Central module for setting up all observability components.
  """

  require Logger
  require OpenTelemetry.Tracer

  def setup do
    # Set up OpenTelemetry logger metadata
    # This adds trace_id and span_id to all log entries
    OpentelemetryLoggerMetadata.setup()

    # Set up OpenTelemetry handlers for telemetry events
    setup_telemetry_handlers()

    # Set up exception tracking
    setup_exception_tracking()

    Logger.info("OpenTelemetry initialized for local development")
  end

  def test_trace do
    # Simple test function to verify traces are being sent
    OpenTelemetry.Tracer.with_span "test_trace" do
      OpenTelemetry.Tracer.set_attributes([{"test.type", "manual"}])
      Logger.info("Executing test trace")

      # Simulate some work
      Process.sleep(100)

      # Add an event
      OpenTelemetry.Tracer.add_event("Test event", %{"event.data" => "test data"})

      # Simulate nested span
      OpenTelemetry.Tracer.with_span "nested_operation" do
        OpenTelemetry.Tracer.set_attributes([{"operation.type", "nested"}])
        Process.sleep(50)
        Logger.info("Nested operation complete")
      end
    end

    {:ok, "Test trace completed"}
  end

  defp setup_telemetry_handlers do
    # Set up handlers for Phoenix
    :ok = OpentelemetryPhoenix.setup()

    # Process propagator doesn't need setup - it's used directly in LiveView processes
    # to fetch parent context when needed

    # Attach to our custom events once we define them
    # This will be expanded in Phase 1
  end

  defp setup_exception_tracking do
    # Will be implemented in Phase 2
    :ok
  end
end
