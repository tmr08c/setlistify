# Working Grafana Cloud OpenTelemetry Configuration for Elixir

This configuration is based on the working example from [Silbernagel.dev](https://silbernagel.dev/posts/elixir-fly-and-grafana-cloud).

## Environment Variables

```bash
# Required
export GRAFANA_CLOUD_API_KEY="your-api-key-here"
export GRAFANA_CLOUD_USER_ID="1219955"  # Your Tempo user ID from Grafana Cloud
export GRAFANA_CLOUD_REGION="us-east-2"  # Your region

# Tempo (Traces) - Working
export GRAFANA_CLOUD_TEMPO_ENDPOINT="https://tempo-prod-26-prod-us-east-2.grafana.net/tempo"

# Loki (Logs) - Working
export GRAFANA_CLOUD_LOKI_ENDPOINT="https://logs-prod-012.grafana.net/loki/api/v1/push"
export GRAFANA_CLOUD_LOKI_USER_ID="1225644"  # Different from Tempo! Check Loki Details page

# Optional
export GRAFANA_CLOUD_ZONE="prod-us-east-0"
```

**Important**: Find your specific endpoints in your Grafana Cloud portal:
- For Tempo: Look in the Tempo data source configuration
- For Loki: Look in the Loki data source configuration or "Details" page

## Configuration (config/runtime.exs)

```elixir
# Determine if we should use Grafana Cloud based on environment variables
use_grafana_cloud = System.get_env("GRAFANA_CLOUD_API_KEY") != nil

if use_grafana_cloud do
  # Grafana Cloud configuration
  grafana_api_key = System.get_env("GRAFANA_CLOUD_API_KEY")
  grafana_region = System.get_env("GRAFANA_CLOUD_REGION", "us-central1")
  grafana_zone = System.get_env("GRAFANA_CLOUD_ZONE")

  # Construct Grafana Cloud endpoints based on region
  # Following the Silbernagel.dev example that works
  tempo_endpoint = "https://tempo-prod-26-prod-#{grafana_region}.grafana.net/tempo"
  
  # For Basic auth, we need user_id:api_key in base64  
  # Use specific user ID from Grafana Cloud Tempo configuration
  grafana_user_id = System.get_env("GRAFANA_CLOUD_USER_ID", "1219955")
  otel_auth = Base.encode64("#{grafana_user_id}:#{grafana_api_key}")

  # Configure OpenTelemetry exporter following the working example
  config :opentelemetry_exporter,
    otlp_protocol: :grpc,
    otlp_traces_endpoint: tempo_endpoint,
    otlp_headers: [{"Authorization", "Basic #{otel_auth}"}]

  # Add zone to resource attributes if provided
  zone_attrs = if grafana_zone, do: [{"cloud.zone", grafana_zone}], else: []
  
  config :opentelemetry, :resource,
    service: [
      name: "setlistify",
      namespace: "setlistify",
      version: "1.0.0"
    ],
    deployment: [
      environment: config_env() |> to_string()
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
else
  # Local OTEL-LGTM configuration (default)
  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf,
    otlp_traces_endpoint: "http://localhost:4318/v1/traces",
    otlp_headers: []

  config :opentelemetry, :resource,
    service: [
      name: "setlistify",
      namespace: "setlistify", 
      version: "1.0.0"
    ],
    deployment: [
      environment: config_env() |> to_string()
    ],
    host: [
      name: System.get_env("HOSTNAME", "localhost")
    ]
end
```

## Loki Configuration (Logs)

The Loki configuration is added alongside the Tempo configuration:

```elixir
# Configure Loki logging for Grafana Cloud
loki_endpoint = System.get_env("GRAFANA_CLOUD_LOKI_ENDPOINT")

if loki_endpoint do
  config :logger,
    backends: [:console, Setlistify.LokiLogger]

  config :logger, Setlistify.LokiLogger,
    url: loki_endpoint,
    username: grafana_user_id,
    password: grafana_api_key,
    level: :info,
    metadata: [:request_id, :trace_id, :span_id, :user_id],
    max_buffer: 100,
    labels: %{
      "application" => "setlistify",
      "environment" => config_env() |> to_string(),
      "instance" => System.get_env("FLY_ALLOC_ID", "unknown"),
      "fly_app" => System.get_env("FLY_APP_NAME", "setlistify"),
      "fly_region" => System.get_env("FLY_REGION", "unknown")
    }
end
```

## Key Differences from Previous Attempts

1. **Use `otlp_traces_endpoint` not `otlp_endpoint`** - This is crucial!
2. **Include `/tempo` in the endpoint URL** for Grafana Cloud
3. **Use the full HTTPS URL** for gRPC protocol
4. **Authorization header format**: `"Basic #{otel_auth}"` not `"Basic " <> otel_auth`
5. **Loki requires its own user ID** - Found in Grafana Cloud > Loki > Details
6. **Loki endpoint must include full path**: `/loki/api/v1/push`

## Testing

### Testing Traces (Tempo)

1. Start your application:
   ```bash
   iex -S mix
   ```

2. Create a test span in IEx:
   ```elixir
   require OpenTelemetry.Tracer
   
   OpenTelemetry.Tracer.with_span "test.grafana_cloud" do
     OpenTelemetry.Tracer.set_attributes([{"test", true}])
     Process.sleep(100)
   end
   
   :otel_batch_processor.force_flush(:global)
   ```

3. Check Grafana Cloud:
   - Go to https://setlistify.grafana.net/explore
   - Select your Tempo data source
   - Search for traces
   - Try an empty query `{}` first to see all traces

### Testing Logs (Loki)

1. Generate test logs in IEx:
   ```elixir
   require Logger
   
   # Generate a log with trace context
   OpenTelemetry.Tracer.with_span "test.loki_logging" do
     Logger.info("Test log from Grafana Cloud integration")
     Logger.error("Test error log with trace context")
   end
   
   # Force flush the logger
   :gen_event.sync_notify(Logger, :flush)
   ```

2. Check Grafana Cloud:
   - Go to https://setlistify.grafana.net/explore
   - Select your Loki data source
   - Try queries like:
     - `{application="setlistify"}`
     - `{application="setlistify", level="error"}`
     - `{application="setlistify"} |= "test"`

## Troubleshooting

### If traces don't appear:

1. Check the logs for "OTLP exporter successfully initialized"
2. Verify environment variables are loaded (check with `System.get_env/1` in IEx)
3. Make sure you're using the Tempo user ID, not the instance ID
4. Check that the region in your endpoint matches your Grafana Cloud setup

### If logs don't appear:

1. Check for any stderr output from LokiLogger: `[LokiLogger] Failed to send logs`
2. Verify the Loki endpoint includes `/loki/api/v1/push`
3. Test authentication with curl:
   ```bash
   curl -v -H "Content-Type: application/json" \
     -u "$GRAFANA_CLOUD_USER_ID:$GRAFANA_CLOUD_API_KEY" \
     -X POST "$GRAFANA_CLOUD_LOKI_ENDPOINT" \
     -d '{"streams": [{"stream": {"application": "test"}, "values": [["1234567890000000000", "test log"]]}]}'
   ```
4. Make sure timestamps are strings (nanoseconds)
5. Check that your labels don't contain invalid characters