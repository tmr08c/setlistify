defmodule Setlistify.Observability.GrafanaTest do
  @moduledoc """
  Test Grafana Cloud trace export
  """
  
  require Logger
  require OpenTelemetry.Tracer
  
  def send_test_traces do
    Logger.info("🚀 Sending test traces to Grafana Cloud...")
    
    # Create a parent span
    OpenTelemetry.Tracer.with_span "grafana_cloud.test_suite" do
      OpenTelemetry.Tracer.set_attributes([
        {"service.name", "setlistify"},
        {"test.type", "grafana_cloud_verification"},
        {"test.timestamp", DateTime.utc_now() |> DateTime.to_iso8601()},
        {"deployment.environment", "development"}
      ])
      
      # Log the trace ID for manual lookup
      ctx = OpenTelemetry.Ctx.get_current()
      span_ctx = OpenTelemetry.Tracer.current_span_ctx(ctx)
      
      if span_ctx != :undefined do
        trace_id = :otel_span.trace_id(span_ctx)
        span_id = :otel_span.span_id(span_ctx)
        
        trace_id_hex = :io_lib.format("~32.16.0b", [trace_id]) |> to_string()
        span_id_hex = :io_lib.format("~16.16.0b", [span_id]) |> to_string()
        
        Logger.info("📍 Root span - trace_id: #{trace_id_hex}, span_id: #{span_id_hex}")
        Logger.info("🔗 Grafana search URL: https://setlistify.grafana.net/explore?left=%7B%22queries%22:%5B%7B%22query%22:%22#{trace_id_hex}%22%7D%5D,%22datasource%22:%22grafanacloud-traces%22%7D")
      end
      
      # Create child spans
      for i <- 1..3 do
        OpenTelemetry.Tracer.with_span "grafana_cloud.test_operation_#{i}" do
          OpenTelemetry.Tracer.set_attributes([
            {"operation.number", i},
            {"operation.name", "test_#{i}"}
          ])
          
          # Add an event
          OpenTelemetry.Tracer.add_event("test_event_#{i}", [
            {"event.data", "test_data_#{i}"}
          ])
          
          # Simulate some work
          :timer.sleep(50)
          
          # Set status
          OpenTelemetry.Tracer.set_status(:ok, "Operation #{i} completed")
        end
      end
      
      # Create an error span
      OpenTelemetry.Tracer.with_span "grafana_cloud.test_error" do
        OpenTelemetry.Tracer.set_attributes([
          {"error.type", "test_error"},
          {"error.simulated", true}
        ])
        
        OpenTelemetry.Tracer.set_status(:error, "Simulated error for testing")
      end
    end
    
    Logger.info("✅ Test traces created")
    Logger.info("⏳ Waiting for export (batch processor delay)...")
    
    # Wait for batch processor (default is 1 second)
    :timer.sleep(5000)
    
    # Check export tables
    export_tables = :ets.all() |> Enum.filter(fn tab ->
      case :ets.info(tab, :name) do
        name when is_atom(name) -> 
          name |> to_string() |> String.contains?("export_table")
        _ -> 
          false
      end
    end)
    
    Enum.each(export_tables, fn table ->
      size = :ets.info(table, :size)
      Logger.info("📊 Export table #{inspect(table)}: #{size} items")
    end)
    
    Logger.info("🏁 Test complete - check Grafana Cloud!")
  end
  
  def check_connection do
    Logger.info("🔍 Checking Grafana Cloud connection...")
    
    # Get configuration
    processors = Application.get_env(:opentelemetry, :processors)
    
    case processors[:otel_batch_processor] do
      %{exporter: {_module, config}} ->
        Logger.info("📡 Exporter config:")
        Logger.info("  Endpoints: #{inspect(config.endpoints)}")
        Logger.info("  Protocol: #{config.protocol}")
        Logger.info("  Headers: #{length(config.headers)} headers configured")
        
        # Decode auth header to verify
        case List.keyfind(config.headers, "authorization", 0) do
          {"authorization", "Basic " <> encoded} ->
            decoded = Base.decode64!(encoded)
            [user_id, _api_key] = String.split(decoded, ":", parts: 2)
            Logger.info("  Auth user ID: #{user_id}")
          _ ->
            Logger.warning("  No authorization header found!")
        end
        
      _ ->
        Logger.error("❌ No batch processor configured!")
    end
    
    # Check if exporter process is alive
    httpc_procs = Process.registered() |> Enum.filter(fn name ->
      name |> to_string() |> String.contains?("httpc_otel_exporter")
    end)
    
    if length(httpc_procs) > 0 do
      Logger.info("✅ OTLP exporter process is running: #{inspect(httpc_procs)}")
    else
      Logger.error("❌ No OTLP exporter process found!")
    end
  end
end