defmodule Setlistify.StructuredLoggerTest do
  use ExUnit.Case
  require Logger
  require OpenTelemetry.Tracer
  alias Setlistify.StructuredLogger
  
  test "adds trace context to log metadata" do
    # Without span context, no trace metadata should be added
    log_event = %{
      meta: %{request_id: "test-123"}
    }
    
    result = StructuredLogger.add_trace_context(log_event, [])
    assert result.meta == %{request_id: "test-123"}
    
    # With span context, trace metadata should be added
    OpenTelemetry.Tracer.with_span "test_span" do
      log_event = %{
        meta: %{request_id: "test-456"}
      }
      
      result = StructuredLogger.add_trace_context(log_event, [])
      assert result.meta[:request_id] == "test-456"
      assert result.meta[:trace_id] != nil
      assert result.meta[:span_id] != nil
      assert is_binary(result.meta[:trace_id])
      assert is_binary(result.meta[:span_id])
    end
  end
end