defmodule Setlistify.Observability.ManualSetup do
  @moduledoc """
  Manual setup to debug OpenTelemetry initialization
  """
  
  require Logger
  
  def diagnose_and_setup do
    Logger.info("🔍 Diagnosing OpenTelemetry setup...")
    
    # Check if apps are started
    otel_apps = [:opentelemetry_api, :opentelemetry, :opentelemetry_exporter]
    
    Enum.each(otel_apps, fn app ->
      case Application.ensure_started(app) do
        :ok -> 
          Logger.info("✅ #{app} already started")
        {:error, {:already_started, ^app}} -> 
          Logger.info("✅ #{app} already started")
        {:error, reason} -> 
          Logger.error("❌ Failed to start #{app}: #{inspect(reason)}")
      end
    end)
    
    # Check if we can get a tracer
    tracer = :opentelemetry.get_tracer()
    Logger.info("📊 Current tracer: #{inspect(tracer)}")
    
    # Check registered tables
    tables = :ets.all() |> Enum.filter(fn tab -> 
      try do
        info = :ets.info(tab, :name)
        info in [:span_tab, :otel_spans_table, :otel_tracer_server]
      rescue
        _ -> false
      end
    end)
    Logger.info("📋 OpenTelemetry ETS tables: #{inspect(tables)}")
    
    # Try to manually create the span table if it doesn't exist
    case :ets.info(:span_tab) do
      :undefined ->
        Logger.warning("⚠️ No span table found - OpenTelemetry might not be properly initialized")
        
        # Force initialization
        Logger.info("🔧 Attempting to force OpenTelemetry initialization...")
        Application.stop(:opentelemetry)
        Application.stop(:opentelemetry_exporter)
        :timer.sleep(100)
        
        {:ok, _} = Application.ensure_all_started(:opentelemetry_exporter)
        {:ok, _} = Application.ensure_all_started(:opentelemetry)
        
        :timer.sleep(500)
        
        case :ets.info(:span_tab) do
          :undefined -> 
            Logger.error("❌ Still no span table after restart")
          info -> 
            Logger.info("✅ Span table created: #{inspect(info)}")
        end
        
      info ->
        Logger.info("✅ Span table exists: #{inspect(info)}")
    end
    
    # Check configuration
    config = Application.get_all_env(:opentelemetry)
    Logger.info("🔧 OpenTelemetry config keys: #{inspect(Keyword.keys(config))}")
    
    # Check if processors are configured
    case Keyword.get(config, :processors) do
      nil -> Logger.error("❌ No processors configured!")
      processors -> Logger.info("✅ Processors configured: #{inspect(Map.keys(processors))}")
    end
  end
  
  def manual_init do
    Logger.info("🚀 Attempting manual OpenTelemetry initialization...")
    
    # Get configuration
    config = Application.get_all_env(:opentelemetry)
    processors_config = Keyword.get(config, :processors, [])
    resource = Keyword.get(config, :resource, [])
    
    Logger.info("📋 Manual init with processors: #{inspect(processors_config)}")
    
    # Try to manually start the SDK
    :application.set_env(:opentelemetry, :processors, processors_config)
    :application.set_env(:opentelemetry, :resource, resource)
    
    # Check if the supervisor is running
    case Process.whereis(:otel_tracer_provider_sup) do
      nil ->
        Logger.warning("⚠️ Tracer provider supervisor not running")
        # Try to start it
        case :otel_tracer_provider_sup.start_link() do
          {:ok, pid} ->
            Logger.info("✅ Started tracer provider supervisor: #{inspect(pid)}")
          {:error, {:already_started, pid}} ->
            Logger.info("ℹ️ Tracer provider supervisor already running: #{inspect(pid)}")
          error ->
            Logger.error("❌ Failed to start tracer provider: #{inspect(error)}")
        end
      pid ->
        Logger.info("✅ Tracer provider supervisor is running: #{inspect(pid)}")
    end
    
    :timer.sleep(500)
    
    # Check again
    case :ets.info(:span_tab) do
      :undefined -> Logger.error("❌ Still no span table")
      info -> Logger.info("✅ Span table now exists: #{inspect(info)}")
    end
  end
end