defmodule Setlistify.Observability.TraceMonitor do
  @moduledoc """
  Monitor OpenTelemetry trace activity
  """
  require Logger
  
  def monitor_export_tables do
    # Find the export tables
    export_tables = :ets.all() |> Enum.filter(fn tab ->
      case :ets.info(tab, :name) do
        name when is_atom(name) -> 
          name |> to_string() |> String.contains?("export_table")
        _ -> 
          false
      end
    end)
    
    Logger.info("📊 Found export tables: #{inspect(export_tables)}")
    
    # Monitor each table
    Enum.each(export_tables, fn table ->
      size = :ets.info(table, :size)
      if size > 0 do
        Logger.info("📤 Export table #{inspect(table)} has #{size} items")
        # Show first item
        case :ets.first(table) do
          :"$end_of_table" -> :ok
          key ->
            case :ets.lookup(table, key) do
              [{_key, value}] ->
                Logger.info("🔍 Sample export item: #{inspect(value, limit: 3)}")
              _ -> :ok
            end
        end
      end
    end)
  end
  
  def check_exporter_process do
    # Look for the httpc process
    httpc_processes = Process.registered() |> Enum.filter(fn name ->
      name |> to_string() |> String.contains?("httpc_otel_exporter")
    end)
    
    Logger.info("🌐 OTLP exporter processes: #{inspect(httpc_processes)}")
    
    # Check if it's alive
    Enum.each(httpc_processes, fn proc ->
      if Process.alive?(Process.whereis(proc)) do
        Logger.info("✅ #{proc} is alive")
      else
        Logger.error("❌ #{proc} is not alive")
      end
    end)
  end
  
  def test_manual_export do
    Logger.info("🧪 Testing manual span creation and export...")
    
    # Create a span using the tracer API
    require OpenTelemetry.Tracer
    
    OpenTelemetry.Tracer.with_span "test.manual_export" do
      OpenTelemetry.Tracer.set_attributes([
        {"test.type", "manual_debug"},
        {"test.timestamp", DateTime.utc_now() |> DateTime.to_iso8601()}
      ])
      :timer.sleep(10)
    end
    
    Logger.info("⏳ Waiting for batch processor...")
    :timer.sleep(1000)
    
    # Check tables
    monitor_export_tables()
    
    # Force export
    Logger.info("💪 Attempting to force batch processor export...")
    case Process.whereis(:otel_batch_processor_global) do
      nil -> 
        Logger.error("❌ No batch processor found")
      pid ->
        Logger.info("📮 Sending force_flush to batch processor #{inspect(pid)}")
        send(pid, :force_flush)
    end
    
    :timer.sleep(1000)
    monitor_export_tables()
  end
end