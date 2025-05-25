defmodule Setlistify.Observability.TestTrace do
  @moduledoc """
  Module to test OpenTelemetry trace generation and export
  """
  
  require Logger
  require OpenTelemetry.Tracer
  
  def send_test_trace do
    Logger.info("🧪 Starting test trace generation...")
    
    OpenTelemetry.Tracer.with_span "test.grafana_cloud_connection" do
      OpenTelemetry.Tracer.set_attributes([
        {"test.type", "manual"},
        {"test.timestamp", DateTime.utc_now() |> DateTime.to_iso8601()},
        {"service.name", "setlistify"},
        {"test.purpose", "grafana_cloud_debug"}
      ])
      
      # Log trace context
      ctx = OpenTelemetry.Ctx.get_current()
      span_ctx = OpenTelemetry.Tracer.current_span_ctx(ctx)
      
      if span_ctx != :undefined do
        trace_id = :otel_span.trace_id(span_ctx)
        span_id = :otel_span.span_id(span_ctx)
        
        trace_id_hex = :io_lib.format("~32.16.0b", [trace_id]) |> to_string()
        span_id_hex = :io_lib.format("~16.16.0b", [span_id]) |> to_string()
        
        Logger.info("📍 Test trace created - trace_id: #{trace_id_hex}, span_id: #{span_id_hex}")
      end
      
      # Create a child span
      OpenTelemetry.Tracer.with_span "test.child_operation" do
        OpenTelemetry.Tracer.set_attributes([
          {"child.attribute", "test_value"}
        ])
        :timer.sleep(50)
      end
      
      # Force an event
      OpenTelemetry.Tracer.add_event("test_event", [{"event.data", "test"}])
      
      :timer.sleep(100)
      OpenTelemetry.Tracer.set_status(:ok, "Test completed")
    end
    
    # Force processor to export (batch processor has a delay)
    Logger.info("⏳ Waiting for batch processor to export...")
    
    # Force the batch processor to export immediately
    try do
      :opentelemetry.force_flush()
    rescue
      _ -> Logger.warning("Could not force flush - using timer instead")
    end
    
    :timer.sleep(1000)
    
    Logger.info("✅ Test trace generation complete - check logs above for export status")
  end
  
  def check_span_table do
    case :ets.info(:span_tab) do
      :undefined ->
        Logger.info("❌ No span table found")
        {:error, :no_span_table}
      info ->
        size = Keyword.get(info, :size, 0)
        Logger.info("📊 Span table has #{size} entries")
        
        if size > 0 do
          spans = :ets.tab2list(:span_tab)
          Logger.info("📋 First span: #{inspect(hd(spans), pretty: true, limit: 3)}")
        end
        
        {:ok, info}
    end
  end
  
  def check_otel_config do
    config = Application.get_all_env(:opentelemetry)
    Logger.info("🔧 OpenTelemetry config: #{inspect(config, pretty: true)}")
    config
  end
end