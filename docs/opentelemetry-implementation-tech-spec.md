
# OpenTelemetry Implementation Tech Spec

## Executive Summary

This document outlines the implementation of OpenTelemetry in Setlistify, our Elixir/Phoenix/LiveView application that integrates Setlist.fm and Spotify APIs to create playlists from concert setlists. OpenTelemetry will provide comprehensive observability through traces, logs, and metrics, starting with a local development stack and eventually deploying to Grafana Cloud. This implementation will be rolled out in phases, beginning with local environment setup, followed by telemetry-to-OpenTelemetry integration, enhanced logging, metrics, and finally cloud deployment.

**Current Status:** Phase 0 completed, Phase 2 partially completed (prioritized for early log visibility), Phase 1 next up.

**Last Updated:** May 22, 2025

## Background

Setlistify is built with Elixir, Phoenix, and LiveView. It integrates with two external APIs (Setlist.fm and Spotify) and uses a sophisticated OAuth token management system for Spotify authentication. The application is deployed to Fly.io. Our primary observability needs are:

1. Tracing OAuth token management flows, particularly the session manager's token refresh operations
2. Monitoring API calls to Setlist.fm and Spotify
3. Tracking LiveView interactions and state changes
4. Correlating logs with traces across our distributed session processes
5. Collecting application and API performance metrics
6. Tracking errors and exceptions, especially API failures and OAuth issues

## Technical Approach

After evaluating several options and initial implementation experimentation, we've decided to:

1. Set up a local development stack with Grafana, Tempo, Loki, and Prometheus
2. **Use `:telemetry` as the primary instrumentation layer**, bridging to OpenTelemetry spans via `opentelemetry_telemetry`
3. Add telemetry events to key modules and operations, then configure handlers to create OpenTelemetry spans
4. Add trace context propagation to HTTP requests using our existing Req client setup
5. Include structured logging with trace context
6. Instrument LiveView processes for user interaction tracing
7. Create custom telemetry events for OAuth flows and API operations
8. Start with local telemetry data collection, then migrate to Grafana Cloud

**Note on Decorator Pattern:** We initially explored implementing a `@trace` decorator pattern for function-level tracing but have decided to postpone this approach (see "Post-Implementation Ideas to Consider" section below).

This approach maintains compatibility with our existing Hammox-based testing strategy while providing comprehensive observability. Special attention will be given to tracing across process boundaries, particularly for our SessionManager and UserSession GenServers. The local-first approach allows for rapid development iteration and testing before cloud deployment.

## Options Considered

### Instrumentation Approach

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Direct OpenTelemetry API | Better cross-process context propagation, Full feature access | Tighter coupling to OpenTelemetry | Rejected |
| `:telemetry` + `opentelemetry_telemetry` | Decoupled from specific backends, Phoenix ecosystem standard, Process boundary handling | Requires more setup, Event-driven rather than decorator-based | **Selected** |
| `@trace` Decorator Pattern | Clean syntax, Automatic instrumentation | Implementation complexity, Process boundary limitations, Community concerns | **Deferred** |
| Custom Tracing Layer | Maximum flexibility | Development overhead, Non-standard | Rejected |

### Backend Service

| Service | Pros | Cons | Decision |
|---------|------|------|----------|
| Honeycomb | Excellent trace-first design, 20M events free tier, High cardinality analysis | Less known technology stack | Initially favored |
| Grafana Cloud | 50GB traces/logs free tier, Good Fly.io integration, Comprehensive platform | Slightly more complex setup | **Selected** |
| SigNoz | Open-source core, Good UI | Smaller free tier (3M spans) | Rejected |
| Self-hosted (Jaeger) | Complete control, No usage limits | Operational overhead | Rejected |
| New Relic | Good APM capabilities | Limited free tier, Complex UI | Rejected |
| Datadog | Comprehensive features | Expensive, Limited OpenTelemetry support | Rejected |

## Technical Details

### 1. Core Libraries and Dependencies

```elixir
# mix.exs
defp deps do
  [
    # OpenTelemetry
    {:opentelemetry_exporter, "~> 1.6.0"},
    {:opentelemetry, "~> 1.3.0"},
    {:opentelemetry_api, "~> 1.2.0"},

    # Framework Integrations
    {:opentelemetry_phoenix, "~> 1.1.0"},
    {:opentelemetry_telemetry, "~> 1.0.0"},
    {:opentelemetry_liveview, "~> 1.0.0"},  # For LiveView instrumentation

    # Telemetry
    {:telemetry, "~> 1.2.1"},
    {:telemetry_metrics, "~> 0.6.1"},

    # Logging - Phase 2 addition
    {:opentelemetry_logger_metadata, "~> 0.2.0"}
  ]
end
```

### 2. Configuration

#### Development Environment Configuration

```elixir
# config/dev.exs

# OpenTelemetry configuration for local development
config :opentelemetry, :processors,
  otel_batch_processor: %{
    exporter: {
      :opentelemetry_exporter,
      %{
        endpoints: [http: "http://localhost:4318/v1/traces"],
        headers: []
      }
    }
  }

# Resource attributes for local development
config :opentelemetry, :resource,
  service: [
    name: "setlistify",
    namespace: "setlistify",
    version: Mix.Project.config()[:version] || "dev"
  ],
  deployment: [
    environment: "development"
  ],
  host: [
    name: System.get_env("HOSTNAME", "localhost")
  ]

# Console logger with trace context (Phase 2)
config :logger, :console,
  format: "$time [$level] $message $metadata\n",
  metadata: [:request_id, :trace_id, :span_id]
```

#### Production Environment Configuration

```elixir
# config/runtime.exs
if config_env() == :prod do
  # OpenTelemetry configuration for Grafana Cloud
  grafana_api_key = System.fetch_env!("GRAFANA_API_KEY")
  grafana_org = System.fetch_env!("GRAFANA_ORG")

  # For Basic auth, encode your org ID and API key
  auth_header = "Basic " <> Base.encode64("#{grafana_org}:#{grafana_api_key}")

  config :opentelemetry, :processors,
    otel_batch_processor: %{
      exporter: {:opentelemetry_exporter, %{
        protocol: :grpc,
        endpoint: "tempo-us-central1.grafana.net:443",
        headers: [
          {"authorization", auth_header}
        ],
        ssl_options: [verify: :verify_peer]
      }}
    }

  # Resource attributes for better identification
  config :opentelemetry, :resource,
    service: [
      name: "setlistify",
      namespace: "setlistify",
      version: Mix.Project.config()[:version] || "dev"
    ],
    deployment: [
      environment: System.get_env("FLY_APP_ENVIRONMENT", "production")
    ],
    host: [
      name: System.get_env("FLY_ALLOC_ID", "local")
    ],
    integrations: [
      spotify: true,
      setlist_fm: true
    ]

  # Loki logger for logs with trace context
  config :logger,
    backends: [:console, LokiLogger]

  config :loki_logger,
    url: System.get_env("LOKI_URL", "https://logs-prod-us-central1.grafana.net/loki/api/v1/push"),
    username: System.get_env("GRAFANA_ORG"),
    password: System.get_env("GRAFANA_API_KEY"),
    level: :info,
    format: :json,
    metadata: [:request_id, :trace_id, :span_id]
end
```

### 3. Local Development Stack

Create a `docker-compose.yml` file in the project root:

```yaml
version: '3.9'

services:
  grafana:
    image: grafana/grafana:latest
    container_name: setlistify-grafana
    environment:
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
      - GF_AUTH_DISABLE_LOGIN_FORM=true
    ports:
      - "3000:3000"
    volumes:
      - ./docker/grafana/datasources:/etc/grafana/provisioning/datasources
      - ./docker/grafana/dashboards:/etc/grafana/provisioning/dashboards
    restart: unless-stopped

  tempo:
    image: grafana/tempo:latest
    container_name: setlistify-tempo
    command: [ "-config.file=/etc/tempo.yaml" ]
    volumes:
      - ./docker/tempo/tempo.yaml:/etc/tempo.yaml
      - ./docker/tempo-data:/var/tempo
    ports:
      - "14268:14268"  # jaeger ingest
      - "3200:3200"    # tempo
      - "9095:9095"    # tempo query
      - "4317:4317"    # otlp grpc
      - "4318:4318"    # otlp http
    restart: unless-stopped

  loki:
    image: grafana/loki:latest
    container_name: setlistify-loki
    command: "-config.file=/etc/loki/local-config.yaml"
    ports:
      - "3100:3100"
    volumes:
      - ./docker/loki/loki-config.yaml:/etc/loki/local-config.yaml
      - ./docker/loki-data:/loki
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:latest
    container_name: setlistify-prometheus
    volumes:
      - ./docker/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./docker/prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    ports:
      - "9090:9090"
    restart: unless-stopped
```

Create necessary configuration files:

```yaml
# docker/tempo/tempo.yaml
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        http:
          endpoint: 0.0.0.0:4318
        grpc:
          endpoint: 0.0.0.0:4317

ingester:
  max_block_duration: 5m

compactor:
  compaction:
    block_retention: 1h

metrics_generator:
  registry:
    external_labels:
      source: tempo
      cluster: docker-compose
  storage:
    path: /var/tempo/generator/wal
    remote_write:
      - url: http://prometheus:9090/api/v1/write
        send_exemplars: true

storage:
  trace:
    backend: local
    wal:
      path: /var/tempo/wal
    local:
      path: /var/tempo/blocks

overrides:
  defaults:
    metrics_generator:
      processors: [service-graphs, span-metrics]
```

```yaml
# docker/loki/loki-config.yaml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    cache_location: /loki/boltdb-shipper-cache
    cache_ttl: 24h
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
```

```yaml
# docker/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'tempo'
    static_configs:
      - targets: ['tempo:3200']
```

```yaml
# docker/grafana/datasources/datasources.yaml
apiVersion: 1

datasources:
  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    basicAuth: false
    isDefault: true
    version: 1
    editable: true
    apiVersion: 1
    uid: tempo
    jsonData:
      httpMethod: GET
      serviceMap:
        datasourceUid: prometheus
      tracesToLogs:
        datasourceUid: loki
        mapTagNamesEnabled: true
        mappedTags:
          - key: service.name
            value: service
      tracesToMetrics:
        datasourceUid: prometheus

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    basicAuth: false
    version: 1
    editable: true
    apiVersion: 1
    uid: loki
    jsonData:
      derivedFields:
        - datasourceUid: tempo
          matcherRegex: "traceID=(\\w+)"
          name: TraceID
          url: '$${__value.raw}'

  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    basicAuth: false
    version: 1
    editable: true
    apiVersion: 1
    uid: prometheus
```

### 5. Core Implementation Components

#### Trace Decorator Module

```elixir
defmodule Setlistify.Trace do
  @moduledoc """
  Provides function decoration for automatic OpenTelemetry tracing.

  Usage:
      defmodule Setlistify.Spotify.API.ExternalClient do
        use Setlistify.Trace

        @trace
        def search_tracks(token, artist, track) do
          # Function body
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      import Setlistify.Trace, only: [trace: 1]
      Module.register_attribute(__MODULE__, :traced_functions, accumulate: true)
      @before_compile Setlistify.Trace
    end
  end

  defmacro __before_compile__(env) do
    traced_functions = Module.get_attribute(env.module, :traced_functions)

    # Register these functions in the telemetry registry if one exists
    if function_exported?(Setlistify.TelemetryEvents, :register_functions, 2) do
      for {name, arity} <- traced_functions do
        Setlistify.TelemetryEvents.register_functions(env.module, name)
      end
    end

    quote do
    end
  end

  defmacro trace(fun) do
    quote do
      @traced_functions {unquote(fun_name(fun)), unquote(fun_arity(fun))}
      unquote(trace_function(fun))
    end
  end

  # Helper to extract function name from AST
  defp fun_name({:def, _, [{name, _, _} | _]}), do: name
  defp fun_name({:defp, _, [{name, _, _} | _]}), do: name

  # Helper to extract function arity from AST
  defp fun_arity({:def, _, [{_, _, args} | _]}), do: length(args || [])
  defp fun_arity({:defp, _, [{_, _, args} | _]}), do: length(args || [])

  # Helper to transform the function with tracing
  defp trace_function({function_type, meta, [head | body]}) do
    # Extract function details
    {fun_name, head_meta, args} = head

    # Create new function body with tracing
    new_body = quote do
      event_name = [__MODULE__ |> Module.split() |> Enum.map(&String.to_atom/1), unquote(fun_name)]
      metadata = %{
        module: __MODULE__,
        function: unquote(fun_name),
        args: unquote(args_to_map(args))
      }

      :telemetry.span(event_name, metadata, fn ->
        result = unquote(body[:do])
        {result, Map.put(metadata, :result, inspect(result))}
      end)
    end

    # Construct the function with tracing
    {function_type, meta, [head, [do: new_body]]}
  end

  # Helper to convert function args to a map for telemetry metadata
  defp args_to_map(args) do
    args
    |> Enum.with_index()
    |> Enum.map(fn
      {{:\\, _, [arg, _default]}, idx} ->
        quote do
          {"arg_#{unquote(idx)}", inspect(unquote(arg))}
        end
      {arg, idx} when is_atom(arg) ->
        quote do
          {"arg_#{unquote(idx)}", inspect(unquote(arg))}
        end
      _ ->
        quote do
          {"args", inspect(unquote(args))}
        end
    end)
    |> then(fn arg_pairs ->
      quote do
        %{unquote_splicing(arg_pairs)}
      end
    end)
  end
end
```

#### Structured Logger with Trace Context

**Note:** In Phase 2, we initially implemented a custom `Setlistify.StructuredLogger` module but later refactored to use the `opentelemetry_logger_metadata` package, which provides a simpler, more maintainable solution.

```elixir
# config/dev.exs - Configuration used in Phase 2
config :logger, :console,
  format: "$time [$level] $message $metadata\n",
  metadata: [:request_id, :trace_id, :span_id]

# lib/setlistify/observability.ex - Setup in Phase 2
def setup do
  # Set up OpenTelemetry logger metadata
  # This adds trace_id and span_id to all log entries
  OpentelemetryLoggerMetadata.setup()

  # ... rest of setup
end
```

The original custom implementation is shown below for reference:

```elixir
defmodule Setlistify.StructuredLogger do
  @moduledoc """
  Provides structured logging with OpenTelemetry trace context.
  (This implementation was replaced with opentelemetry_logger_metadata)
  """

  require Logger

  def setup do
    # Add OpenTelemetry Logger metadata handler
    :logger.add_handler_filter(:default, :add_trace_context, {&add_trace_context/2, []})
  end

  @doc """
  Filter function that adds trace context to log metadata.
  """
  def add_trace_context(log_event, _config) do
    # Get current context
    ctx = OpenTelemetry.Ctx.get_current()
    span_ctx = OpenTelemetry.Tracer.current_span_ctx()

    metadata = case span_ctx do
      :undefined -> %{}
      _ ->
        # Extract trace and span IDs
        trace_id = span_ctx |> OpenTelemetry.Span.trace_id() |> Base.encode16(case: :lower)
        span_id = span_ctx |> OpenTelemetry.Span.span_id() |> Base.encode16(case: :lower)
        %{trace_id: trace_id, span_id: span_id}
    end

    # Update the log event metadata
    %{log_event | meta: Map.merge(log_event.meta || %{}, metadata)}
  end

  # ... rest of module omitted
end
```

#### HTTP Client with Trace Propagation

```elixir
defmodule Setlistify.TracedReq do
  @moduledoc """
  Provides a Req plugin that adds OpenTelemetry trace propagation
  and instrumentation to all HTTP requests to external APIs.
  This module enhances our existing API clients for Setlist.fm and Spotify.
  """

  def attach do
    # Register the plugin with req
    Req.update([
      plugins: [
        {Setlistify.TracedReq.Plugin, []}
      ]
    ])
  end

  defmodule Plugin do
    @moduledoc false

    @behaviour Req.Request.Plugin

    @impl true
    def init(request, options) do
      # Map external API domains to service names for better tracing
      service_names = %{
        "api.setlist.fm" => "setlist-fm-api",
        "api.spotify.com" => "spotify-api",
        "accounts.spotify.com" => "spotify-auth"
      }

      {request, Map.put(options, :service_names, service_names)}
    end

    @impl true
    def request(request, options) do
      # Get the current trace context
      ctx = OpenTelemetry.Ctx.get_current()

      # Extract service name
      uri = URI.parse(request.url)
      service_name = Map.get(options.service_names, uri.host, uri.host || "unknown-service")

      # Create span name from the request
      path = uri.path || "/"
      method = request.method || :get
      span_name = "#{method} #{service_name}#{path}"

      OpenTelemetry.Tracer.with_span span_name do
        # Set span attributes
        OpenTelemetry.Tracer.set_attributes([
          {"http.method", to_string(method)},
          {"http.url", request.url},
          {"http.target", path},
          {"peer.service", service_name}
        ])

        # Inject trace headers into the request
        headers = OpenTelemetry.Propagator.text_map_injector().inject(ctx, %{})
        headers = Enum.map(headers, fn {k, v} -> {to_string(k), v} end)

        # Update request with trace headers
        request = Req.Request.append_request_headers(request, headers)

        # Execute the request
        {request, options}
      end
    end

    @impl true
    def response(request, options, response) do
      # Extract status code
      status = response.status

      # Record the status in the current span
      OpenTelemetry.Tracer.set_attribute("http.status_code", status)

      # Mark error if status >= 400
      if status >= 400 do
        OpenTelemetry.Tracer.set_status(:error, "HTTP Error #{status}")
      end

      # Emit telemetry event for metrics
      uri = URI.parse(request.url)
      service_name = Map.get(options.service_names, uri.host, uri.host || "unknown-service")
      path = uri.path || "/"
      method = request.method || :get

      measurements = %{
        duration: response.time,
        response_size: byte_size(to_string(response.body))
      }

      metadata = %{
        service: service_name,
        endpoint: "#{method} #{path}",
        status: status
      }

      :telemetry.execute([:my_app, :api_client, :request, :stop], measurements, metadata)

      {request, options, response}
    end

    @impl true
    def error(request, options, error) do
      # Record the error in the current span
      OpenTelemetry.Tracer.set_status(:error, "HTTP Request Failed: #{inspect(error)}")
      OpenTelemetry.Tracer.add_event("http.error", %{"error" => inspect(error)})

      # Emit telemetry event for the error
      uri = URI.parse(request.url)
      service_name = Map.get(options.service_names, uri.host, uri.host || "unknown-service")
      path = uri.path || "/"
      method = request.method || :get

      :telemetry.execute(
        [:my_app, :api_client, :request, :exception],
        %{},
        %{
          service: service_name,
          endpoint: "#{method} #{path}",
          error: error
        }
      )

      {request, options, error}
    end
  end

  # Convenience helpers
  def get(url, options \\ []), do: Req.get(url, options)
  def post(url, body, options \\ []), do: Req.post(url, [{:body, body} | options])
  def put(url, body, options \\ []), do: Req.put(url, [{:body, body} | options])
  def delete(url, options \\ []), do: Req.delete(url, options)
end
```

#### Telemetry Event Registry

```elixir
defmodule Setlistify.TelemetryEvents do
  @moduledoc """
  Registry of telemetry events for Setlistify application.
  """

  # Use a module attribute to store the registered events
  @registered_events []

  # Store the registered events at compile time
  @before_compile {__MODULE__, :__before_compile__}

  defmacro __before_compile__(_env) do
    registered_events = Module.get_attribute(__CALLER__.module, :registered_events)

    quote do
      @doc """
      Returns all registered telemetry events.
      """
      def all_events do
        unquote(Macro.escape(registered_events))
      end
    end
  end

  @doc """
  Register a new telemetry event.
  """
  defmacro register(name, event_name, doc) do
    # Add the event to the registry
    events = Module.get_attribute(__CALLER__.module, :registered_events)
    event = {name, event_name, doc}
    Module.put_attribute(__CALLER__.module, :registered_events, [event | events])

    quote do
      @doc unquote(doc)
      def unquote(name)() do
        unquote(event_name)
      end
    end
  end

  # Register events for Spotify OAuth and Session Management
  register :spotify_auth_login_start, [:setlistify, :spotify, :auth, :login, :start],
    "Emitted when a Spotify OAuth flow begins"

  register :spotify_auth_callback, [:setlistify, :spotify, :auth, :callback],
    "Emitted when processing Spotify OAuth callback"

  register :spotify_token_refresh_start, [:setlistify, :spotify, :token_refresh, :start],
    "Emitted when a Spotify token refresh begins"

  register :spotify_token_refresh_stop, [:setlistify, :spotify, :token_refresh, :stop],
    "Emitted when a Spotify token refresh completes"

  register :spotify_token_refresh_exception, [:setlistify, :spotify, :token_refresh, :exception],
    "Emitted when a Spotify token refresh fails with an exception"

  register :spotify_session_created, [:setlistify, :spotify, :session, :created],
    "Emitted when a new Spotify session is created"

  register :spotify_session_terminated, [:setlistify, :spotify, :session, :terminated],
    "Emitted when a Spotify session is terminated"

  # Register events for API operations
  register :setlist_search_start, [:setlistify, :setlist_fm, :search, :start],
    "Emitted when searching for setlists"

  register :setlist_search_stop, [:setlistify, :setlist_fm, :search, :stop],
    "Emitted when setlist search completes"

  register :setlist_fetch_start, [:setlistify, :setlist_fm, :fetch, :start],
    "Emitted when fetching a specific setlist"

  register :spotify_track_search_start, [:setlistify, :spotify, :track, :search, :start],
    "Emitted when searching for tracks on Spotify"

  register :spotify_playlist_create_start, [:setlistify, :spotify, :playlist, :create, :start],
    "Emitted when creating a playlist on Spotify"

  # Register LiveView events
  register :liveview_mount, [:setlistify, :liveview, :mount],
    "Emitted when a LiveView mounts"

  register :liveview_search_submit, [:setlistify, :liveview, :search, :submit],
    "Emitted when a user submits a search"

  register :liveview_playlist_create, [:setlistify, :liveview, :playlist, :create],
    "Emitted when a user creates a playlist from a setlist"

  @doc """
  Verify at compile time that an event is registered.
  """
  defmacro verify_event!(event_name) do
    registered_events = Module.get_attribute(__CALLER__.module, :registered_events)
    event_exists = Enum.any?(registered_events, fn {_, event, _} ->
      event == Macro.expand(event_name, __CALLER__)
    end)

    unless event_exists do
      raise CompileError,
        description: "Telemetry event #{inspect(event_name)} is not registered",
        file: __CALLER__.file,
        line: __CALLER__.line
    end

    quote do
      unquote(event_name)
    end
  end

  @doc """
  Register functions discovered through the @trace attribute.
  """
  def register_functions(module, function_name) do
    # Convert module name to event path
    module_path = module
      |> Module.split()
      |> Enum.map(&String.to_atom/1)

    # Register the events for start, stop, and exception
    event_prefix = module_path ++ [function_name]

    # Dynamic registration (runtime)
    event_name_start = event_prefix ++ [:start]
    event_name_stop = event_prefix ++ [:stop]
    event_name_exception = event_prefix ++ [:exception]
  end
end
```

#### LiveView Telemetry (Implemented in Phase 2)

```elixir
defmodule SetlistifyWeb.Telemetry.LiveViewTelemetry do
  @moduledoc """
  Creates a new span for LiveView processes since they don't inherit HTTP trace context.
  """

  import Phoenix.LiveView
  require Logger
  require OpenTelemetry.Tracer

  def on_mount(:default, _params, _session, socket) do
    # Since LiveView processes don't naturally inherit trace context,
    # we'll create a new span for each LiveView mount
    if connected?(socket) do
      # For connected LiveView (WebSocket), create a new trace
      OpenTelemetry.Tracer.with_span "liveview.mount" do
        OpenTelemetry.Tracer.set_attributes([
          {"liveview.module", inspect(socket.view)},
          {"liveview.connected", true}
        ])

        Logger.info("LiveView telemetry: Created new span for connected LiveView")
      end
    end

    {:cont, socket}
  end
end
```

#### Telemetry Setup

```elixir
defmodule Setlistify.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      # Start the telemetry application poller
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Runtime Metrics
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.system_counts.process_count"),

      # HTTP Metrics
      counter("phoenix.endpoint.start.count", tags: [:route]),
      distribution("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond},
        tags: [:route, :status]
      ),

      # LiveView Metrics
      counter("phoenix.live_view.mount.count", tags: [:view, :status]),
      counter("phoenix.live_view.handle_event.count", tags: [:view, :event]),

      # Spotify OAuth Metrics
      counter("setlistify.spotify.token_refresh.count", tags: [:status]),
      distribution("setlistify.spotify.token_refresh.duration",
        unit: {:native, :millisecond},
        tags: [:status]
      ),
      counter("setlistify.spotify.session.count", tags: [:action]),

      # API Client Metrics
      counter("setlistify.api_client.request.count",
        tags: [:service, :endpoint, :status]
      ),
      distribution("setlistify.api_client.request.duration",
        unit: {:native, :millisecond},
        tags: [:service, :endpoint, :status]
      ),
      counter("setlistify.api_client.error.count",
        tags: [:service, :endpoint, :error_type]
      ),

      # Business Metrics
      counter("setlistify.search.count", tags: [:type]),
      counter("setlistify.playlist.created.count"),
      distribution("setlistify.playlist.tracks.count"),

      # Error Metrics
      counter("setlistify.error.count",
        tags: [:type, :module]
      )
    ]
  end

  defp periodic_measurements do
    [
      # VM Measurements
      {:process_info, :all},
      {:vm_measurements, [:memory, :total_run_queue_lengths]},
      {:system_info, [:process_count]}
    ]
  end
end
```

#### Main Application Setup

```elixir
defmodule Setlistify.Observability do
  @moduledoc """
  Central module for setting up all observability components.
  """

  def setup do
    # Set up OpenTelemetry handlers for telemetry events
    setup_telemetry_handlers()

    # Set up structured logging
    Setlistify.StructuredLogger.setup()

    # Set up Req with trace propagation
    Setlistify.TracedReq.attach()

    # Set up telemetry metrics
    Setlistify.Telemetry.start_link([])

    # Set up exception tracking
    setup_exception_tracking()
  end

  defp setup_telemetry_handlers do
    # Set up handlers for your custom events
    [
      {MyApp.TelemetryEvents.auth_login_start(), "user_login"},
      {MyApp.TelemetryEvents.auth_token_refresh_start(), "token_refresh"}
      # Add more events as needed
    ]
    |> Enum.each(fn {event_prefix, span_name} ->
      attach_otel_handlers(event_prefix, span_name)
    end)

    # Add handlers for Phoenix and other framework events
    OpentelemetryPhoenix.setup(adapter: :cowboy2)
  end

  defp attach_otel_handlers(event_prefix, span_name) do
    start_event = event_prefix
    stop_event = Enum.drop(start_event, -1) ++ [:stop]
    exception_event = Enum.drop(start_event, -1) ++ [:exception]

    handler_id = "otel-#{Enum.join(event_prefix, "-")}"

    :telemetry.attach(
      "#{handler_id}-start",
      start_event,
      &OpentelemetryTelemetry.start_telemetry_span/4,
      %{tracer_id: :my_app, span_name: span_name}
    )

    :telemetry.attach(
      "#{handler_id}-stop",
      stop_event,
      &OpentelemetryTelemetry.end_telemetry_span/4,
      %{tracer_id: :my_app}
    )

    :telemetry.attach(
      "#{handler_id}-exception",
      exception_event,
      &OpentelemetryTelemetry.end_telemetry_span/4,
      %{tracer_id: :my_app}
    )
  end

  defp setup_exception_tracking do
    # Add a custom Logger backend for exception tracking
    Logger.add_backend(MyApp.ExceptionLogger)

    # Set up a process error handler if using Phoenix
    if Code.ensure_loaded?(Phoenix) do
      # Add this to your Router module
      # use MyApp.ErrorHandler
    end
  end
end

defmodule MyApp.ExceptionLogger do
  @behaviour :gen_event

  def init(_) do
    {:ok, %{}}
  end

  def handle_event({level, _gl, {Logger, msg, timestamp, metadata}}, state)
      when level in [:error, :critical, :alert, :emergency] do
    # Create a span for this logged error
    OpenTelemetry.Tracer.with_span "logged_error" do
      OpenTelemetry.Tracer.set_attribute("error", true)
      OpenTelemetry.Tracer.set_attribute("log.level", to_string(level))
      OpenTelemetry.Tracer.set_attribute("log.message", to_string(msg))

      # Add exception details if available
      if ex = metadata[:error] do
        OpenTelemetry.Tracer.set_attribute("error.type", inspect(ex.__struct__))
        OpenTelemetry.Tracer.set_attribute("error.message", Exception.message(ex))
      end

      if stack = metadata[:stacktrace] do
        OpenTelemetry.Tracer.set_attribute("error.stack", inspect(stack))
      end

      OpenTelemetry.Tracer.set_status(:error, "Logged error")

      # Emit a telemetry event for the error
      error_type = if ex = metadata[:error], do: inspect(ex.__struct__), else: "unknown"
      module = metadata[:module] || "unknown"

      :telemetry.execute(
        [:my_app, :error, :count],
        %{count: 1},
        %{type: error_type, module: module}
      )
    end

    {:ok, state}
  end

  def handle_event(_event, state) do
    {:ok, state}
  end

  # Implement other callbacks...
end
```

### 5. Application-Specific Instrumentation

#### 5.1 Key Modules to Monitor

The following modules represent critical paths in Setlistify and should be instrumented with OpenTelemetry:

**API Clients**
- `lib/setlistify/spotify/api/external_client.ex` - Spotify API integration
- `lib/setlistify/setlist_fm/api/external_client.ex` - Setlist.fm API integration

**Session Management**
- `lib/setlistify/spotify/session_manager.ex` - GenServer managing user sessions
- `lib/setlistify/spotify/user_session.ex` - Individual session GenServers
- `lib/setlistify/spotify/session_supervisor.ex` - Supervisor for session processes

**Web Interface**
- `lib/setlistify_web/live/search_live.ex` - Main search interface
- `lib/setlistify_web/live/setlists/show_live.ex` - Setlist display
- `lib/setlistify_web/live/playlists/show_live.ex` - Playlist display
- `lib/setlistify_web/controllers/oauth_callback_controller.ex` - OAuth handling

**Authentication & Authorization**
- `lib/setlistify_web/controllers/user_auth.ex` - User authentication
- `lib/setlistify_web/plugs/restore_spotify_token.ex` - Token restoration
- `lib/setlistify_web/auth/live_hooks.ex` - LiveView auth hooks

#### 5.2 Instrumentation Examples

##### Spotify API Client Instrumentation

```elixir
defmodule Setlistify.Spotify.API.ExternalClient do
  @behaviour Setlistify.Spotify.API
  use Setlistify.Trace
  alias Setlistify.StructuredLogger, as: Logger

  # Instrument token refresh logic
  @trace
  defp with_token_refresh(user_session, request_fn, context) do
    :telemetry.span(
      [:setlistify, :spotify, :api, :token_refresh_wrapper],
      %{user_id: user_session.user_id, context: context},
      fn ->
        req = client(user_session)

        case request_fn.(req) do
          {:ok, %{status: 401} = response} ->
            # Track token expiration events
            :telemetry.execute(
              [:setlistify, :spotify, :token, :expired],
              %{count: 1},
              %{user_id: user_session.user_id, context: context}
            )

            # Existing refresh logic...
            if authenticate_header && String.contains?(authenticate_value, "invalid_token") do
              case SessionManager.refresh_session(user_session.user_id) do
                {:ok, new_session} ->
                  Logger.info("Token refreshed", %{
                    user_id: user_session.user_id,
                    context: context,
                    trace_id: OpenTelemetry.Tracer.current_span_id()
                  })
                  {request_fn.(client(new_session)), %{refreshed: true}}

                {:error, reason} ->
                  {{:error, :token_refresh_failed}, %{refresh_error: reason}}
              end
            else
              {{:ok, response}, %{refreshed: false}}
            end

          other ->
            {other, %{refreshed: false}}
        end
      end
    )
  end

  # Instrument search operations
  @trace
  def search_for_track(user_session, artist, track) do
    Logger.info("Searching for track", %{
      artist: artist,
      track: track,
      user_id: user_session.user_id
    })

    :telemetry.span(
      [:setlistify, :spotify, :search, :track],
      %{artist: artist, track: track, user_id: user_session.user_id},
      fn ->
        request_fn = fn req ->
          Req.get(req,
            url: "/search",
            params: %{q: "artist:#{artist} track:#{track}", type: "track"}
          )
        end

        case with_token_refresh(user_session, request_fn, "track search") do
          {:ok, %{status: 200} = resp} ->
            items = resp.body |> Map.get("tracks", %{}) |> Map.get("items", [])

            result =
              with nil <- List.first(items) do
                Logger.warning("No search results", %{artist: artist, track: track})
                nil
              else
                track_info ->
                  Logger.info("Found match", %{artist: artist, track: track})
                  %{uri: track_info["uri"], preview_url: track_info["preview_url"]}
              end

            {result, %{status: :success, results_count: length(items)}}

          {:error, reason} = error ->
            Logger.error("Search failed", %{
              artist: artist,
              track: track,
              error: reason
            })
            {error, %{status: :failed, error: reason}}

          other ->
            {other, %{status: :unexpected}}
        end
      end
    )
  end

  # Instrument OAuth code exchange
  @trace
  def exchange_code(code, redirect_uri) do
    :telemetry.span(
      [:setlistify, :spotify, :oauth, :exchange],
      %{redirect_uri: redirect_uri},
      fn ->
        # Implementation with telemetry metadata...
      end
    )
  end
end
```

##### Setlist.fm API Client Instrumentation

```elixir
defmodule Setlistify.SetlistFm.API.ExternalClient do
  @behaviour Setlistify.SetlistFm.API
  use Setlistify.Trace
  alias Setlistify.StructuredLogger, as: Logger

  @trace
  def search(query, endpoint \\ @root_endpoint) do
    :telemetry.span(
      [:setlistify, :setlist_fm, :search],
      %{query: query, endpoint: endpoint},
      fn ->
        start_time = System.monotonic_time()

        result =
          Req.get!(request(endpoint),
            url: "/search/setlists",
            params: %{"artistName" => query}
          )

        duration = System.monotonic_time() - start_time

        setlists = result.body["setlist"] || []

        Logger.info("Setlist search completed", %{
          query: query,
          results_count: length(setlists),
          duration_ms: System.convert_time_unit(duration, :native, :millisecond)
        })

        mapped_results = Enum.map(setlists, &transform_setlist/1)

        {mapped_results, %{
          status: :success,
          count: length(setlists),
          duration_ms: System.convert_time_unit(duration, :native, :millisecond)
        }}
      end
    )
  rescue
    error ->
      Logger.error("Setlist search error", %{
        query: query,
        error: error,
        stacktrace: __STACKTRACE__
      })

      :telemetry.execute(
        [:setlistify, :setlist_fm, :error],
        %{count: 1},
        %{operation: :search, error_type: error.__struct__}
      )

      reraise error, __STACKTRACE__
  end

  @trace
  def get_setlist(id, endpoint \\ @root_endpoint) do
    :telemetry.span(
      [:setlistify, :setlist_fm, :get_setlist],
      %{setlist_id: id, endpoint: endpoint},
      fn ->
        resp = Req.get!(request(endpoint), url: "/setlist/#{id}")

        setlist_data = resp.body
        artist_name = get_in(setlist_data, ["artist", "name"])
        sets = get_in(setlist_data, ["sets", "set"]) || []
        total_songs = Enum.reduce(sets, 0, fn set, acc ->
          songs = Map.get(set, "song", [])
          acc + length(songs)
        end)

        result = transform_single_setlist(setlist_data)

        {result, %{
          status: :success,
          artist: artist_name,
          total_songs: total_songs,
          sets_count: length(sets)
        }}
      end
    )
  end
end
```

##### LiveView Instrumentation (Partially Implemented in Phase 2)

```elixir
defmodule SetlistifyWeb.SearchLive do
  use SetlistifyWeb, :live_view
  use Gettext, backend: SetlistifyWeb.Gettext

  require Logger
  require OpenTelemetry.Tracer

  def mount(_params, _session, socket) do
    # Note: Phase 2 implemented LiveViewTelemetry hook that creates spans during mount
    {:ok, assign(socket, setlists: [], search: search_form(%{}))}
  end

  def handle_params(params, _uri, socket) do
    # Create a span for the handle_params operation (Added in Phase 2)
    OpenTelemetry.Tracer.with_span "search_live.handle_params" do
      OpenTelemetry.Tracer.set_attributes([
        {"query", inspect(params)}
      ])

      Logger.info("Log inside custom span looking for #{inspect(params)}")

      search_form = search_form(params)
      search_changeset = search_form.source

      setlists =
        if search_changeset.valid? do
          search_changeset |> Ecto.Changeset.get_field(:query) |> Setlistify.SetlistFm.API.search()
        else
          []
        end

      {:noreply, assign(socket, search: search_form, setlists: setlists)}
    end
  end

  def handle_event("search", %{"search" => params}, socket) do
    # TODO: Add telemetry span as shown below
    # :telemetry.span(
    #   [:setlistify, :live_view, :handle_event],
    #   %{event: "search", query: params["q"], view: "SearchLive"},
    #   fn ->
        {:noreply, socket |> push_patch(to: "/#{encode_query_string(params)}")}
    #   end
    # )
  end
end
```

### 6. Testing Strategy

Testing is crucial for ensuring our OpenTelemetry implementation works correctly without breaking existing functionality. Each implementation phase includes specific testing approaches.

#### 6.1 Phase 1 Testing - Core Tracing Infrastructure

**Unit Tests for Trace Decorator**
```elixir
defmodule Setlistify.TraceTest do
  use ExUnit.Case
  import Hammox

  setup :verify_on_exit!

  describe "@trace decorator" do
    test "creates telemetry span for traced function" do
      defmodule TestModule do
        use Setlistify.Trace

        @trace
        def test_function(arg) do
          {:ok, arg}
        end
      end

      # Assert telemetry event is emitted
      self = self()

      :telemetry.attach(
        "test-handler",
        [:test_module, :test_function, :start],
        fn event, measurements, metadata, _config ->
          send(self, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      TestModule.test_function("test")

      assert_receive {:telemetry_event, [:test_module, :test_function, :start], _, _}
    end
  end
end
```

**Integration Tests for API Clients**
```elixir
defmodule Setlistify.Spotify.API.ExternalClientIntegrationTest do
  use ExUnit.Case
  import Hammox

  setup :verify_on_exit!

  describe "with telemetry instrumentation" do
    test "emits span events for API calls" do
      # Setup Hammox expectation
      expect(
        Setlistify.Spotify.API.MockClient,
        :search_for_track,
        fn _session, "artist", "track" ->
          %{uri: "spotify:track:123", preview_url: nil}
        end
      )

      # Attach telemetry handler
      self = self()

      :telemetry.attach_many(
        "test-handler",
        [
          [:setlistify, :spotify, :search, :track, :start],
          [:setlistify, :spotify, :search, :track, :stop]
        ],
        fn event, _measurements, metadata, _config ->
          send(self, {:telemetry_event, event, metadata})
        end,
        nil
      )

      # Execute the function
      session = %UserSession{user_id: "test", access_token: "token"}
      result = Setlistify.Spotify.API.MockClient.search_for_track(session, "artist", "track")

      # Verify telemetry events
      assert_receive {:telemetry_event, [:setlistify, :spotify, :search, :track, :start], metadata}
      assert metadata.artist == "artist"
      assert metadata.track == "track"

      assert_receive {:telemetry_event, [:setlistify, :spotify, :search, :track, :stop], metadata}
      assert metadata.status == :success
    end
  end
end
```

**Testing Token Refresh Instrumentation**
```elixir
defmodule Setlistify.Spotify.TokenRefreshTest do
  use ExUnit.Case, async: true

  test "token refresh emits telemetry events" do
    # Setup test handlers
    self = self()

    :telemetry.attach(
      "refresh-test",
      [:setlistify, :spotify, :token_refresh, :start],
      fn _event, _measurements, metadata, _config ->
        send(self, {:token_refresh_started, metadata})
      end,
      nil
    )

    # Trigger token refresh via SessionManager
    {:ok, _session} = SessionManager.refresh_session("test_user_id")

    assert_receive {:token_refresh_started, %{user_id: "test_user_id"}}
  end
end
```

#### 6.2 Phase 2 Testing - Enhanced Tracing and Logging

**Structured Logger Tests**
```elixir
defmodule Setlistify.StructuredLoggerTest do
  use ExUnit.Case

  test "adds trace context to log metadata" do
    # Create a span context
    OpenTelemetry.Tracer.with_span "test_span" do
      Setlistify.StructuredLogger.info("Test message", %{key: "value"})

      # Capture logged output
      assert_receive {:log, level, message, metadata}
      assert level == :info
      assert message == "Test message"
      assert metadata[:trace_id] != nil
      assert metadata[:span_id] != nil
      assert metadata[:key] == "value"
    end
  end

  test "handles errors with stacktraces" do
    try do
      raise "Test error"
    rescue
      e ->
        Setlistify.StructuredLogger.error("Error occurred", %{
          error: e,
          stacktrace: __STACKTRACE__
        })

        assert_receive {:log, :error, _, metadata}
        assert metadata[:error] != nil
        assert metadata[:stacktrace] != nil
    end
  end
end
```

**LiveView Instrumentation Tests**
```elixir
defmodule SetlistifyWeb.SearchLiveTest do
  use SetlistifyWeb.ConnCase
  import Phoenix.LiveViewTest

  test "mount emits telemetry event", %{conn: conn} do
    self = self()

    :telemetry.attach(
      "liveview-test",
      [:setlistify, :live_view, :mount],
      fn _event, _measurements, metadata, _config ->
        send(self, {:mount_event, metadata})
      end,
      nil
    )

    {:ok, _view, _html} = live(conn, "/")

    assert_receive {:mount_event, %{view: "SearchLive"}}
  end

  test "search event creates span", %{conn: conn} do
    self = self()

    :telemetry.attach(
      "search-test",
      [:setlistify, :live_view, :handle_event, :start],
      fn _event, _measurements, metadata, _config ->
        send(self, {:search_event, metadata})
      end,
      nil
    )

    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#search-form", %{q: "Radiohead"})
    |> render_submit()

    assert_receive {:search_event, %{event: "search", query: "Radiohead"}}
  end
end
```

#### 6.3 Phase 3 Testing - Metrics and Dashboards

**Metrics Collection Tests**
```elixir
defmodule Setlistify.TelemetryTest do
  use ExUnit.Case

  test "collects API request metrics" do
    ref = make_ref()

    # Subscribe to telemetry events
    :telemetry_metrics.attach(
      "test-metrics",
      [:setlistify, :api_client, :request, :stop],
      fn _event, measurements, metadata, _config ->
        send(self(), {:metric, ref, measurements, metadata})
      end,
      nil
    )

    # Trigger an API request
    :telemetry.execute(
      [:setlistify, :api_client, :request, :stop],
      %{duration: 100_000_000},  # 100ms in nanoseconds
      %{service: "spotify-api", endpoint: "GET /search", status: 200}
    )

    assert_receive {:metric, ^ref, measurements, metadata}
    assert measurements.duration == 100_000_000
    assert metadata.service == "spotify-api"
    assert metadata.status == 200
  end

  test "tracks error counts by type" do
    ref = make_ref()

    :telemetry_metrics.attach(
      "error-metrics",
      [:setlistify, :error, :count],
      fn _event, measurements, metadata, _config ->
        send(self(), {:error_metric, ref, measurements, metadata})
      end,
      nil
    )

    # Simulate different error types
    :telemetry.execute(
      [:setlistify, :error, :count],
      %{count: 1},
      %{type: "TokenRefreshError", module: "Setlistify.Spotify.SessionManager"}
    )

    assert_receive {:error_metric, ^ref, %{count: 1}, metadata}
    assert metadata.type == "TokenRefreshError"
    assert metadata.module == "Setlistify.Spotify.SessionManager"
  end
end
```

**End-to-End Observability Tests**
```elixir
defmodule Setlistify.ObservabilityE2ETest do
  use ExUnit.Case

  @tag :integration
  test "full request flow creates connected traces" do
    # This test verifies that traces are properly connected
    # from LiveView -> API client -> external service

    # Start a root span
    OpenTelemetry.Tracer.with_span "e2e_test" do
      # Simulate user search
      {:ok, results} = Setlistify.search_artist("Radiohead")

      # Verify we created child spans
      current_span = OpenTelemetry.Tracer.current_span_ctx()
      assert current_span != :undefined

      # In a real test, you would query your telemetry backend
      # to verify the trace structure
    end
  end
end
```

#### 6.4 Phase 4 Testing - Optimization

**Performance Impact Tests**
```elixir
defmodule Setlistify.PerformanceTest do
  use ExUnit.Case

  @tag :benchmark
  test "instrumentation overhead is acceptable" do
    # Measure baseline without instrumentation
    {baseline_time, _} = :timer.tc(fn ->
      Enum.each(1..1000, fn _ ->
        # Simulate API call without telemetry
        :timer.sleep(1)
      end)
    end)

    # Measure with instrumentation
    {instrumented_time, _} = :timer.tc(fn ->
      Enum.each(1..1000, fn _ ->
        :telemetry.span(
          [:test, :operation],
          %{},
          fn ->
            :timer.sleep(1)
            {:ok, %{}}
          end
        )
      end)
    end)

    overhead_percent = ((instrumented_time - baseline_time) / baseline_time) * 100

    # Assert overhead is less than 5%
    assert overhead_percent < 5.0,
      "Instrumentation overhead too high: #{overhead_percent}%"
  end
end
```

#### 6.5 Test Configuration

**Test-Specific Configuration**
```elixir
# config/test.exs
config :setlistify, :telemetry,
  enabled: false  # Disable telemetry exports in tests by default

config :opentelemetry,
  traces_exporter: :none  # Disable trace exports

# For integration tests that need telemetry
config :setlistify, :telemetry_integration_tests,
  enabled: true

# test/test_helper.exs
if System.get_env("TELEMETRY_TESTS") == "true" do
  Application.put_env(:setlistify, :telemetry, enabled: true)
end
```

**Mock Setup for API Tests**
```elixir
# test/support/telemetry_test_helpers.ex
defmodule Setlistify.TelemetryTestHelpers do
  @moduledoc """
  Helpers for testing telemetry instrumentation
  """

  def capture_telemetry_events(event_names) do
    test_pid = self()

    handler_id = "test-handler-#{:erlang.unique_integer()}"

    :telemetry.attach_many(
      handler_id,
      event_names,
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  def assert_telemetry_event(event_name, timeout \\ 1000) do
    assert_receive {:telemetry_event, ^event_name, _, _}, timeout
  end
end
```

## Deployment Configuration

### Environment Variables

For Fly.io deployment, you'll need to set the following secrets alongside your existing Spotify and Setlist.fm API keys:

```bash
# Set Grafana Cloud credentials
fly secrets set GRAFANA_API_KEY=your_api_key
fly secrets set GRAFANA_ORG=your_org_name

# Set Loki URL for logs
fly secrets set LOKI_URL=https://logs-prod-us-central1.grafana.net/loki/api/v1/push

# Your existing secrets remain:
# - SPOTIFY_CLIENT_ID
# - SPOTIFY_CLIENT_SECRET
# - SETLIST_FM_API_SECRET
```

### Fly.toml Updates

Add the following to your `fly.toml` to ensure proper OTel configuration:

```toml
[env]
  OTEL_SERVICE_NAME = "setlistify"
  OTEL_RESOURCE_ATTRIBUTES = "service.name=setlistify,deployment.environment=production"

[processes]
  app = "bin/setlistify start"
```

## Implementation Plan

### Phase 0: Local Development Stack Setup ✅ COMPLETED

**Tasks Completed:**
1. ✅ Created docker-compose.yml with Grafana stack
2. ✅ Created configuration files for Tempo, Loki, and Prometheus
3. ✅ Added development environment configuration to config/dev.exs
4. ✅ Configured OpenTelemetry to send data to local endpoints
5. ✅ Created bin/otel-local script for managing docker stack
6. ✅ Verified services are running and accessible
7. ✅ Tested connectivity and successfully sent traces from Elixir app
8. ✅ Created basic dashboard for trace visualization
9. ✅ Documented local setup process

**Commit:** 74f4b1d - "feat: add OpenTelemetry local development environment"

### Phase 2: Enhanced Tracing and Logging (Local) ✅ COMPLETED (Partial)

**Implementation Approach:** We started with Phase 2 to gain immediate visibility into trace context in logs, which helps with debugging during Phase 1 implementation.

**Tasks Completed:**
1. ✅ Implemented logger with trace context correlation using `opentelemetry_logger_metadata`
2. ✅ Added trace context (trace_id and span_id) to development logs
3. ✅ Implemented LiveView process trace propagation
4. ✅ Basic instrumentation of SearchLive with custom spans
5. ✅ Added dependency to mix.exs

**Commits:**
- fb90497 - "feat: implement Phase 2 - add trace context to logs"
- 455e899 - "refactor: replace custom StructuredLogger with opentelemetry_logger_metadata"

### Phase 1: Telemetry-to-OpenTelemetry Integration

**Status:** NEXT UP

**Tasks:**
1. Complete OpenTelemetry dependencies in mix.exs
2. Implement Setlistify.TelemetryEvents registry
3. Create Setlistify.Observability.setup_telemetry_otel_bridges/0
4. Add `:telemetry.span/3` instrumentation to key modules:
   - `lib/setlistify/spotify/api/external_client.ex`
   - `lib/setlistify/setlist_fm/api/external_client.ex` 
   - `lib/setlistify/spotify/session_manager.ex`
   - `lib/setlistify/spotify/user_session.ex`
   - `lib/setlistify_web/controllers/oauth_callback_controller.ex`
5. Configure telemetry handlers to bridge to OpenTelemetry spans
6. Enhance existing LiveView instrumentation with more telemetry events
7. Add telemetry events for critical business operations:
   - OAuth flows and token refresh
   - API request patterns and retries
   - Session lifecycle management
8. Create integration tests for telemetry-to-OpenTelemetry flow
9. Test locally with docker stack
10. Verify connected traces across process boundaries

**Testing Focus:**
- Integration tests for telemetry event emission
- Verify OpenTelemetry span creation from telemetry events
- Test trace context propagation across GenServer boundaries
- Manual validation with local Grafana UI

**Expected Timeline:** 2-3 days
**Dependencies:** Phase 0 completion ✅, Phase 2 partial completion ✅
**Key Success Metrics:** 
- Connected traces visible in local Grafana showing OAuth flow
- Trace context properly propagated across SessionManager → UserSession → API calls
- LiveView interactions create spans linked to business operations

### Phase 2: Enhanced Tracing and Logging (Local) - Complete Remaining Tasks

**Tasks Remaining:**
1. Add Loki logger configuration for local development
2. Create exception tracking for API errors and OAuth failures
3. Implement HTTP client tracing with Req middleware
4. Complete comprehensive LiveView instrumentation
5. Add telemetry events for error scenarios and edge cases
6. Create structured tests for telemetry instrumentation
7. Verify log correlation with traces in local Grafana

**Testing Focus:**
- Exception handling with trace context
- HTTP client request tracing
- Log correlation verification in Grafana
- LiveView event flow testing

**Expected Timeline:** 1-2 days
**Dependencies:** Phase 1 completion
**Key Success Metrics:** Complete observability stack with logs correlated to traces

### Phase 3: Metrics and Dashboards (Local)

**Tasks:**
1. Implement Setlistify.Telemetry metrics collection
2. Set up metrics reporting to local Prometheus
3. Create custom telemetry metrics for business operations
4. Build Grafana dashboards for:
   - Application health and performance
   - OAuth session metrics
   - API performance and error rates
   - Business metrics (searches, playlists created)
5. Set up local alerts for key failure scenarios
6. Create performance baselines with metrics
7. Test metrics accuracy and dashboard functionality

**Expected Timeline:** 1-2 days
**Dependencies:** Phase 1 and Phase 2 completion
**Key Success Metrics:** Operational dashboards showing real-time application metrics

### Phase 4: Optimization and Refinement (Local)

**Tasks:**
1. Analyze performance impact of telemetry instrumentation
2. Optimize high-frequency telemetry events
3. Implement sampling strategies for development vs production
4. Create SLO definitions and tracking
5. Document observability architecture and patterns
6. Create operational runbooks
7. Performance test full instrumentation stack
8. Refine dashboards based on usage patterns

**Expected Timeline:** 1-2 days
**Dependencies:** Phase 3 completion
**Key Success Metrics:** Minimal performance overhead, comprehensive documentation

### Phase 5: Cloud Deployment

**Tasks:**
1. Set up Grafana Cloud account and credentials
2. Update production configuration for cloud endpoints
3. Configure Fly.io secrets and environment variables
4. Import dashboards and configure cloud alerts
5. Deploy and validate telemetry data flow
6. Monitor costs and optimize for free tier limits
7. Update documentation for production setup

**Expected Timeline:** 1 day
**Dependencies:** Phase 4 completion
**Key Success Metrics:** Production telemetry flowing to Grafana Cloud within free tier limits

## Testing Strategy

Testing is crucial for ensuring our OpenTelemetry implementation works correctly without breaking existing functionality.

### Integration Tests for Telemetry Events

```elixir
defmodule Setlistify.TelemetryIntegrationTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  describe "telemetry event emission" do
    test "Spotify API search emits telemetry events" do
      # Capture telemetry events
      ref = make_ref()
      self = self()

      :telemetry.attach_many(
        "test-handler-#{ref}",
        [
          [:setlistify, :spotify, :track, :search, :start],
          [:setlistify, :spotify, :track, :search, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(self, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      # Execute the function that should emit events
      session = %UserSession{user_id: "test", access_token: "token"}
      _result = Setlistify.Spotify.API.ExternalClient.search_for_track(session, "Radiohead", "Creep")

      # Verify events were emitted
      assert_receive {:telemetry_event, ^ref, [:setlistify, :spotify, :track, :search, :start], _measurements, metadata}
      assert metadata.artist == "Radiohead"
      assert metadata.track == "Creep"

      assert_receive {:telemetry_event, ^ref, [:setlistify, :spotify, :track, :search, :stop], _measurements, _metadata}

      :telemetry.detach("test-handler-#{ref}")
    end

    test "Session Manager operations emit telemetry events" do
      ref = make_ref()
      self = self()

      :telemetry.attach(
        "session-test-#{ref}",
        [:setlistify, :session_manager, :create_session, :start],
        fn event, measurements, metadata, _config ->
          send(self, {:session_event, ref, event, metadata})
        end,
        nil
      )

      # Test session creation
      {:ok, _session} = Setlistify.Spotify.SessionManager.create_session("test_user", %{})

      assert_receive {:session_event, ^ref, [:setlistify, :session_manager, :create_session, :start], metadata}
      assert metadata.user_id == "test_user"

      :telemetry.detach("session-test-#{ref}")
    end
  end
end
```

### OpenTelemetry Bridge Tests

```elixir
defmodule Setlistify.OpenTelemetryBridgeTest do
  use ExUnit.Case

  test "telemetry events create OpenTelemetry spans" do
    # Start a root span for the test
    OpenTelemetry.Tracer.with_span "test_span" do
      # Execute a function that emits telemetry
      :telemetry.span(
        [:setlistify, :test, :operation],
        %{test_data: "value"},
        fn ->
          # Verify we're in a span context
          current_span = OpenTelemetry.Tracer.current_span_ctx()
          assert current_span != :undefined
          
          {:ok, %{result: "success"}}
        end
      )
    end
  end

  test "exception handling creates error spans" do
    assert_raise RuntimeError, "Test error", fn ->
      :telemetry.span(
        [:setlistify, :test, :error],
        %{},
        fn ->
          raise "Test error"
        end
      )
    end

    # In a real test, you'd verify the span was marked as an error
  end
end
```

## Success Criteria

1. **Complete trace visibility of OAuth token lifecycle** (login, refresh, expiry)
2. **End-to-end traces for user flows** (search → setlist → playlist creation)
3. **Automatic error tracking for API failures** with retry context
4. **Log correlation with trace context** across GenServer boundaries
5. **Real-time metrics for API performance** and rate limiting
6. **LiveView performance insights** (mount times, event latencies)
7. **Operational dashboards** for monitoring session health
8. **Business dashboards** for usage patterns
9. **Alert configuration** for critical failures
10. **Cross-process trace continuity** from HTTP requests through GenServers to external APIs

## Conclusion

This implementation provides comprehensive observability for Setlistify using a telemetry-first approach that integrates cleanly with OpenTelemetry. By focusing on `:telemetry` events as the primary instrumentation mechanism, we:

- Maintain compatibility with existing testing strategies
- Follow Elixir community best practices
- Enable flexible instrumentation without tight coupling
- Support effective cross-process tracing
- Keep code explicit and maintainable

The decision to postpone the `@trace` decorator pattern allows us to focus on proven, flexible approaches while keeping the door open for future enhancements. The local-first development approach ensures we can iterate quickly and validate our observability strategy before deploying to production.

**Current Progress Summary:**
- **Phase 0**: ✅ Complete - Local development stack operational
- **Phase 2**: ✅ Partial - Trace context in logs, LiveView spans working
- **Phase 1**: 🎯 Next - Telemetry-to-OpenTelemetry integration for core flows
