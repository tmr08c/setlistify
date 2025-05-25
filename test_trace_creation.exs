# Simple test to verify OpenTelemetry is working
# Run this in your running app's IEx console

# Test creating a span manually
require OpenTelemetry.Tracer

IO.puts("🧪 Testing trace creation...")

OpenTelemetry.Tracer.with_span "test.manual_span" do
  OpenTelemetry.Tracer.set_attributes([
    {"test.attribute", "manual_test"},
    {"service.name", "setlistify"},
    {"test.timestamp", DateTime.utc_now() |> DateTime.to_iso8601()}
  ])
  
  # Get current trace context
  ctx = OpenTelemetry.Ctx.get_current()
  span_ctx = OpenTelemetry.Tracer.current_span_ctx(ctx)
  
  if span_ctx != :undefined do
    trace_id = :otel_span.trace_id(span_ctx)
    span_id = :otel_span.span_id(span_ctx)
    
    IO.puts("✅ Span created successfully!")
    IO.puts("   Trace ID: #{:io_lib.format("~16.16.0b", [trace_id])}")
    IO.puts("   Span ID: #{:io_lib.format("~16.16.0b", [span_id])}")
  else
    IO.puts("❌ No span context found")
  end
  
  # Simulate some work
  :timer.sleep(100)
  
  OpenTelemetry.Tracer.set_status(:ok, "Test completed successfully")
end

IO.puts("🏁 Test completed - check your Grafana Cloud for the test span!")