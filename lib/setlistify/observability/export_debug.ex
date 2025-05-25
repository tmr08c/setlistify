defmodule Setlistify.Observability.ExportDebug do
  @moduledoc """
  Debug OpenTelemetry export issues
  """
  
  require Logger
  
  def check_export_status do
    Logger.info("🔍 Checking OpenTelemetry export status...")
    
    # Check batch processor
    case Process.whereis(:otel_batch_processor_global) do
      nil ->
        Logger.error("❌ No batch processor found!")
      pid ->
        Logger.info("✅ Batch processor running: #{inspect(pid)}")
        
        # Get process info
        info = Process.info(pid, [:message_queue_len, :messages])
        Logger.info("📬 Message queue length: #{info[:message_queue_len]}")
        
        if info[:message_queue_len] > 0 do
          Logger.warning("⚠️ Batch processor has #{info[:message_queue_len]} queued messages")
        end
    end
    
    # Check span table
    case :ets.info(:otel_span_table) do
      :undefined ->
        Logger.error("❌ No span table!")
      info ->
        size = Keyword.get(info, :size, 0)
        Logger.info("📊 Span table size: #{size}")
        
        if size > 0 do
          Logger.info("📋 Spans waiting to be processed")
          # Show a sample span
          case :ets.first(:otel_span_table) do
            :"$end_of_table" -> :ok
            key ->
              case :ets.lookup(:otel_span_table, key) do
                [span] ->
                  Logger.info("🔍 Sample span: #{inspect(span, limit: 3)}")
                _ -> :ok
              end
          end
        end
    end
    
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
      Logger.info("📤 Export table #{inspect(table)}: #{size} items")
      
      if size > 0 do
        Logger.warning("⚠️ Export table has items - might indicate export issues")
      end
    end)
    
    # Check HTTP client process
    httpc_procs = Process.registered() |> Enum.filter(fn name ->
      name |> to_string() |> String.contains?("httpc_otel_exporter")
    end)
    
    Enum.each(httpc_procs, fn proc ->
      if pid = Process.whereis(proc) do
        info = Process.info(pid, [:message_queue_len, :status])
        Logger.info("🌐 #{proc} - Status: #{info[:status]}, Queue: #{info[:message_queue_len]}")
      end
    end)
  end
  
  def test_grpc_endpoint do
    Logger.info("🧪 Testing gRPC endpoint connectivity...")
    
    endpoint = "tempo-prod-26-prod-us-east-2.grafana.net"
    
    # Test DNS resolution
    case :inet.gethostbyname(String.to_charlist(endpoint)) do
      {:ok, {:hostent, _name, _aliases, :inet, _version, addresses}} ->
        Logger.info("✅ DNS resolution successful: #{inspect(addresses)}")
        
        # Test TCP connection to gRPC port
        addr = hd(addresses)
        case :gen_tcp.connect(addr, 443, [:binary, active: false], 5000) do
          {:ok, socket} ->
            Logger.info("✅ TCP connection to port 443 successful")
            :gen_tcp.close(socket)
          {:error, reason} ->
            Logger.error("❌ TCP connection failed: #{reason}")
        end
        
      {:error, reason} ->
        Logger.error("❌ DNS resolution failed: #{reason}")
    end
  end
end