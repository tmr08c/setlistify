defmodule Mix.Tasks.Otel.Test do
  @moduledoc """
  Tests OpenTelemetry configuration by creating sample traces.

  This task will:
  - Start the OpenTelemetry applications
  - Create a test trace with nested spans
  - Include an error scenario
  - Display trace and span IDs for verification in Grafana

  ## Usage

      $ mix otel.test

  ## Options

      * `--simple` - Create only a simple trace without nested spans
      * `--error` - Create only error traces for testing error reporting

  ## Examples

      $ mix otel.test
      $ mix otel.test --simple
      $ mix otel.test --error

  After running, check Grafana at http://localhost:3000 to see the traces.
  """

  use Mix.Task
  require Logger
  require OpenTelemetry.Tracer

  @shortdoc "Tests OpenTelemetry by creating sample traces"

  @impl Mix.Task
  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Parse arguments
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [simple: :boolean, error: :boolean]
      )

    IO.puts("\n🔍 OpenTelemetry Test")
    IO.puts("====================\n")

    cond do
      opts[:simple] -> create_simple_trace()
      opts[:error] -> create_error_trace()
      true -> create_full_trace()
    end

    IO.puts("\nWaiting for traces to export...")
    Process.sleep(3000)

    IO.puts("\n📊 To view your traces:")
    IO.puts("   1. Open Grafana: http://localhost:3000")
    IO.puts("   2. Go to Explore → Tempo")
    IO.puts("   3. Search by TraceID or use the Search tab")
    IO.puts("\n✨ Test completed!")
  end

  defp create_simple_trace do
    IO.puts("Creating simple trace...\n")

    OpenTelemetry.Tracer.with_span "otel.test.simple" do
      ctx = OpenTelemetry.Tracer.current_span_ctx()
      trace_id = format_trace_id(ctx)
      span_id = format_span_id(ctx)

      IO.puts("📍 Simple trace created:")
      IO.puts("   Trace ID: #{trace_id}")
      IO.puts("   Span ID:  #{span_id}")

      OpenTelemetry.Tracer.set_attributes([
        {"test.type", "simple"},
        {"test.timestamp", DateTime.utc_now() |> DateTime.to_iso8601()},
        {"test.mix_env", Mix.env() |> Atom.to_string()}
      ])

      Logger.info("Simple test trace created")
      Process.sleep(100)
    end
  end

  defp create_error_trace do
    IO.puts("Creating error trace...\n")

    OpenTelemetry.Tracer.with_span "otel.test.error" do
      ctx = OpenTelemetry.Tracer.current_span_ctx()
      trace_id = format_trace_id(ctx)
      span_id = format_span_id(ctx)

      IO.puts("📍 Error trace created:")
      IO.puts("   Trace ID: #{trace_id}")
      IO.puts("   Span ID:  #{span_id}")

      OpenTelemetry.Tracer.set_attributes([
        {"test.type", "error"},
        {"error.expected", true}
      ])

      # Simulate different error scenarios
      OpenTelemetry.Tracer.with_span "otel.test.error.exception" do
        try do
          raise RuntimeError, "Test exception for OpenTelemetry"
        rescue
          e ->
            OpenTelemetry.Tracer.record_exception(e)
            OpenTelemetry.Tracer.set_status(:error, Exception.message(e))
            Logger.error("Test exception recorded")
        end
      end

      OpenTelemetry.Tracer.with_span "otel.test.error.manual" do
        OpenTelemetry.Tracer.set_status(:error, "Manual error for testing")

        OpenTelemetry.Tracer.add_event("error_occurred", %{
          "error.type" => "validation",
          "error.message" => "Invalid input (test)"
        })

        Logger.error("Manual error recorded")
      end
    end
  end

  defp create_full_trace do
    IO.puts("Creating full trace with nested spans...\n")

    OpenTelemetry.Tracer.with_span "otel.test.parent" do
      parent_ctx = OpenTelemetry.Tracer.current_span_ctx()
      trace_id = format_trace_id(parent_ctx)
      span_id = format_span_id(parent_ctx)

      IO.puts("📍 Parent span:")
      IO.puts("   Trace ID: #{trace_id}")
      IO.puts("   Span ID:  #{span_id}")

      OpenTelemetry.Tracer.set_attributes([
        {"test.type", "full"},
        {"service.name", "setlistify"},
        {"test.user", System.get_env("USER", "unknown")}
      ])

      # Add an event
      OpenTelemetry.Tracer.add_event("test_started", %{
        "event.timestamp" => System.system_time(:millisecond)
      })

      Process.sleep(50)

      # Nested operation - simulating API call
      OpenTelemetry.Tracer.with_span "otel.test.api_call" do
        child_ctx = OpenTelemetry.Tracer.current_span_ctx()
        child_span_id = format_span_id(child_ctx)

        IO.puts("\n📍 API call span:")
        IO.puts("   Trace ID: #{trace_id} (inherited)")
        IO.puts("   Span ID:  #{child_span_id}")

        OpenTelemetry.Tracer.set_attributes([
          {"http.method", "GET"},
          {"http.url", "https://api.example.com/test"},
          {"http.status_code", 200}
        ])

        Process.sleep(75)

        # Nested database query
        OpenTelemetry.Tracer.with_span "otel.test.db_query" do
          OpenTelemetry.Tracer.set_attributes([
            {"db.operation", "SELECT"},
            {"db.statement", "SELECT * FROM test_table LIMIT 10"}
          ])

          Process.sleep(25)
        end
      end

      # Add completion event
      OpenTelemetry.Tracer.add_event("test_completed", %{
        "event.duration_ms" => 150
      })

      Logger.info("Full test trace completed")
    end
  end

  defp format_trace_id(ctx) do
    :otel_span.hex_trace_id(ctx)
  end

  defp format_span_id(ctx) do
    :otel_span.hex_span_id(ctx)
  end
end
