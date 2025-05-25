defmodule Setlistify.Observability.SDKStarter do
  @moduledoc """
  A GenServer to ensure OpenTelemetry SDK is properly started
  """
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    Logger.info("🚀 Starting OpenTelemetry SDK initialization...")
    
    # Configure OpenTelemetry before starting
    configure_opentelemetry()
    
    # Now start OpenTelemetry with the new configuration
    Logger.info("📦 Starting OpenTelemetry applications...")
    apps = [:opentelemetry_api, :opentelemetry_exporter, :opentelemetry]
    
    Enum.each(apps, fn app ->
      case Application.ensure_all_started(app) do
        {:ok, started} ->
          Logger.info("✅ Started #{app} and dependencies: #{inspect(started)}")
        {:error, {app, reason}} ->
          Logger.error("❌ Failed to start #{app}: #{inspect(reason)}")
      end
    end)
    
    # Check if the debug exporter was initialized
    :timer.sleep(500)
    
    # Give it a moment to initialize
    Process.sleep(1000)
    
    # Check if span table exists now
    case :ets.info(:span_tab) do
      :undefined ->
        Logger.error("❌ No span table after OpenTelemetry start - checking processes...")
        
        # List all registered processes
        registered = Process.registered() |> Enum.filter(fn name ->
          name |> to_string() |> String.contains?("otel")
        end)
        Logger.info("📋 OpenTelemetry processes: #{inspect(registered)}")
        
      info ->
        Logger.info("✅ Span table exists: #{inspect(Keyword.get(info, :size, 0))} entries")
    end
    
    # Now set up instrumentation
    Setlistify.Observability.setup()
    
    {:ok, %{}}
  end
  
  defp configure_opentelemetry do
    # Ensure .env is loaded in dev
    if Mix.env() == :dev do
      case DotenvParser.load_file(".env") do
        :ok -> :ok
        {:error, _} -> Logger.warning("Could not load .env file")
      end
    end
    
    # Load environment variables
    use_grafana_cloud = System.get_env("GRAFANA_CLOUD_API_KEY") != nil
    
    if use_grafana_cloud do
      Logger.info("🌩️ Configuring OpenTelemetry for Grafana Cloud...")
      
      grafana_api_key = System.get_env("GRAFANA_CLOUD_API_KEY")
      grafana_user_id = System.get_env("GRAFANA_CLOUD_USER_ID", "1219955")
      grafana_region = System.get_env("GRAFANA_CLOUD_REGION", "us-central1")
      grafana_zone = System.get_env("GRAFANA_CLOUD_ZONE")
      
      # Construct Grafana Cloud endpoints
      tempo_endpoint = "tempo-prod-26-prod-#{grafana_region}.grafana.net"
      auth_header = "Basic " <> Base.encode64("#{grafana_user_id}:#{grafana_api_key}")
      
      Logger.info("📍 Tempo endpoint: #{tempo_endpoint}")
      
      # Set debug exporter for dev environment
      exporter_module = if Mix.env() == :dev do
        Setlistify.Observability.DebugExporter
      else
        :opentelemetry_exporter
      end
      
      # Configure processors - must be a list!
      processor_config = [
        otel_batch_processor: %{
          exporter: {
            exporter_module,
            %{
              protocol: :grpc,
              endpoints: [tempo_endpoint],
              headers: [
                {"authorization", auth_header}
              ],
              compression: :gzip
            }
          }
        }
      ]
      
      # Configure resource attributes
      zone_attrs = if grafana_zone, do: [{"cloud.zone", grafana_zone}], else: []
      resource_config = [
        service: [
          name: "setlistify",
          namespace: "setlistify",
          version: "1.0.0"
        ],
        deployment: [
          environment: Mix.env() |> to_string()
        ],
        host: [
          name: System.get_env("FLY_ALLOC_ID", "local")
        ],
        telemetry: [
          sdk: [
            name: "opentelemetry",
            language: "elixir"
          ]
        ],
        cloud: [
          provider: "grafana",
          region: grafana_region
        ] ++ zone_attrs
      ]
      
      # Apply configuration
      Application.put_env(:opentelemetry, :processors, processor_config)
      Application.put_env(:opentelemetry, :resource, resource_config)
      Application.put_env(:opentelemetry, :traces_exporter, :otlp)
      
      Logger.info("✅ Grafana Cloud configuration applied")
      
      # Stop and restart OpenTelemetry with new config
      Logger.info("🔄 Restarting OpenTelemetry with new configuration...")
      Application.stop(:opentelemetry)
      Application.stop(:opentelemetry_exporter)
      :timer.sleep(100)
    else
      Logger.info("🏠 Using local OpenTelemetry configuration")
      
      # Local configuration - must be a list!
      processor_config = [
        otel_batch_processor: %{
          exporter: {
            :opentelemetry_exporter,
            %{
              endpoints: [http: "http://localhost:4318/v1/traces"],
              headers: []
            }
          }
        }
      ]
      
      resource_config = [
        service: [
          name: "setlistify",
          namespace: "setlistify", 
          version: "1.0.0"
        ],
        deployment: [
          environment: Mix.env() |> to_string()
        ],
        host: [
          name: System.get_env("HOSTNAME", "localhost")
        ]
      ]
      
      Application.put_env(:opentelemetry, :processors, processor_config)
      Application.put_env(:opentelemetry, :resource, resource_config)
      
      # Stop OpenTelemetry if it's running
      Logger.info("🔄 Restarting OpenTelemetry with local configuration...")
      Application.stop(:opentelemetry)
      Application.stop(:opentelemetry_exporter)
      :timer.sleep(100)
    end
  end
end