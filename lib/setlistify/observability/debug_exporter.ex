defmodule Setlistify.Observability.DebugExporter do
  @moduledoc """
  A wrapper around the OpenTelemetry exporter that logs export attempts
  for debugging Grafana Cloud connectivity issues.
  """
  
  require Logger

  def init(config) do
    Logger.info("🔍 DebugExporter: Initializing with config: #{inspect(config, pretty: true)}")
    
    # Initialize the actual exporter
    case :opentelemetry_exporter.init(config) do
      {:ok, state} ->
        Logger.info("✅ DebugExporter: Successfully initialized OpenTelemetry exporter")
        {:ok, {state, config}}
      
      {:error, reason} = error ->
        Logger.error("❌ DebugExporter: Failed to initialize: #{inspect(reason)}")
        error
    end
  end

  def export(spans_or_tid, resource, {exporter_state, config}) do
    # Handle both export/3 and export/4 calls
    spans = case spans_or_tid do
      tid when is_reference(tid) or is_atom(tid) ->
        # It's a table reference, get the spans
        :ets.tab2list(tid)
      spans when is_list(spans) ->
        spans
    end
    
    span_count = length(spans)
    Logger.info("📤 DebugExporter: Attempting to export #{span_count} spans")
    
    # Log first span details for debugging
    if span_count > 0 do
      first_span = hd(spans)
      Logger.debug("📊 First span details: #{inspect(first_span, pretty: true, limit: 5)}")
    end
    
    # Log endpoint info
    Logger.debug("🌐 Export config: #{inspect(config, pretty: true)}")
    
    start_time = System.monotonic_time(:millisecond)
    
    # Call the actual exporter
    result = :opentelemetry_exporter.export(spans, resource, exporter_state)
    
    duration = System.monotonic_time(:millisecond) - start_time
    
    case result do
      :ok ->
        Logger.info("✅ DebugExporter: Successfully exported #{span_count} spans in #{duration}ms")
        :ok
      
      {:error, reason} = error ->
        Logger.error("❌ DebugExporter: Export failed after #{duration}ms: #{inspect(reason)}")
        error
      
      other ->
        Logger.warning("⚠️ DebugExporter: Unexpected export result after #{duration}ms: #{inspect(other)}")
        other
    end
  end

  def shutdown({exporter_state, _config}) do
    Logger.info("🛑 DebugExporter: Shutting down")
    :opentelemetry_exporter.shutdown(exporter_state)
  end
end