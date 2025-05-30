# Working Grafana Cloud OpenTelemetry Configuration for Elixir

This configuration is based on the working example from [Silbernagel.dev](https://silbernagel.dev/posts/elixir-fly-and-grafana-cloud).

## Environment Variables

```bash
# Required
export GRAFANA_CLOUD_API_KEY="your-api-key-here"
export GRAFANA_CLOUD_USER_ID="1219955"  # Your Tempo user ID from Grafana Cloud
export GRAFANA_CLOUD_REGION="us-east-2"  # Your region

# Optional
export GRAFANA_CLOUD_ZONE="prod-us-east-0"

# PromEx Dashboard Configuration
export GRAFANA_CLOUD_STACK_NAME="setlistify"  # Your Grafana Cloud stack name
export GRAFANA_DATASOURCE_ID="grafanacloud-setlistify-prom"  # Prometheus datasource name for dashboards
```

### Where to Find These Values

1. **GRAFANA_CLOUD_API_KEY**: 
   - Go to Grafana Cloud Console → Administration → Access Policies
   - Create a new access policy with metrics:write and traces:write scopes
   - Generate a new token

2. **GRAFANA_CLOUD_USER_ID**: 
   - Go to Grafana Cloud Console → Tempo → Details
   - Look for "User" field (numeric ID like "1219955")

3. **GRAFANA_CLOUD_REGION**: 
   - Visible in your Grafana Cloud Console URL or instance details
   - Examples: "us-east-2", "us-central1", "eu-west-0"

4. **GRAFANA_CLOUD_ZONE**: 
   - Go to Grafana Cloud Console → instance details
   - Examples: "prod-us-east-0", "prod-eu-west-0"

5. **GRAFANA_CLOUD_STACK_NAME**: 
   - This is your Grafana Cloud stack name (usually your organization/project name)
   - Visible in your Grafana URL: `https://{stack-name}.grafana.net`

6. **GRAFANA_DATASOURCE_ID**: 
   - Automatically follows the pattern: `grafanacloud-{stack-name}-prom`
   - Used by PromEx for dashboard uploads to reference the correct Prometheus datasource

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

## Key Differences from Previous Attempts

1. **Use `otlp_traces_endpoint` not `otlp_endpoint`** - This is crucial!
2. **Include `/tempo` in the endpoint URL** for Grafana Cloud
3. **Use the full HTTPS URL** for gRPC protocol
4. **Authorization header format**: `"Basic #{otel_auth}"` not `"Basic " <> otel_auth`

## Testing

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

## Troubleshooting

If traces don't appear:

1. Check the logs for "OTLP exporter successfully initialized"
2. Verify environment variables are loaded (check with `System.get_env/1` in IEx)
3. Make sure you're using the Tempo user ID, not the instance ID
4. Check that the region in your endpoint matches your Grafana Cloud setup