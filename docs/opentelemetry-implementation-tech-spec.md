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

After evaluating several options and conducting implementation experimentation, we've decided to:

1. Set up a local development stack with Grafana, Tempo, Loki, and Prometheus
2. **Use OpenTelemetry directly** for instrumentation and observability
3. Leverage official OpenTelemetry integrations (`opentelemetry_phoenix`, `opentelemetry_ecto`, etc.) for automatic framework instrumentation
4. Add manual instrumentation using `OpenTelemetry.Tracer.with_span/2` for business logic
5. Add trace context propagation to HTTP requests using our existing Req client setup
6. Include structured logging with trace context (already implemented in Phase 2)
7. Instrument LiveView processes for user interaction tracing
8. Start with local telemetry data collection, then migrate to Grafana Cloud

**Key Decision: Direct OpenTelemetry over Telemetry Bridge:** We initially explored using `:telemetry` events bridged to OpenTelemetry spans via `opentelemetry_telemetry`, but decided against this approach after research and evaluation (see "Evaluation of Telemetry Bridge Approach" section below).

**Note on Decorator Pattern:** We initially explored implementing a `@trace` decorator pattern for function-level tracing but have decided to postpone this approach (see "Post-Implementation Ideas to Consider" section below).

This approach maintains compatibility with our existing Hammox-based testing strategy while providing comprehensive observability. Special attention will be given to tracing across process boundaries, particularly for our SessionManager and UserSession GenServers. The local-first approach allows for rapid development iteration and testing before cloud deployment.

## Options Considered

### Instrumentation Approach

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Direct OpenTelemetry API | Full feature access, Better cross-process context propagation, Community standard approach, Rich ecosystem | Requires learning OpenTelemetry APIs | **Selected** |
| `:telemetry` + `opentelemetry_telemetry` | Decoupled from specific backends, Phoenix ecosystem standard | **Critical limitations: spans only correlated within single process, outdated bridge library, community reports issues** | **Rejected** |
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

## Evaluation of Telemetry Bridge Approach

During the planning phase, we thoroughly evaluated using `:telemetry` events as the primary instrumentation mechanism, bridging to OpenTelemetry spans via the `opentelemetry_telemetry` library. However, after researching community experiences and reviewing the library's limitations, we decided against this approach.

### Critical Limitations Discovered

**1. Single-Process Span Correlation**
The `opentelemetry_telemetry` documentation clearly states: *"Span contexts are currently stored in the process dictionary, so spans can only be correlated within a single process at this time."* ([source](https://hexdocs.pm/opentelemetry_telemetry/OpentelemetryTelemetry.html#module-limitations))

This is a fundamental issue for Setlistify's architecture, which involves:
- HTTP requests → LiveView processes
- LiveView → SessionManager GenServer
- SessionManager → UserSession GenServer
- UserSession → API calls (potentially in separate processes/tasks)

**2. Library Maturity and Community Experience**
Community reports indicate issues with the bridge library:
- *"I've found the opentelemetry_telemetry library, but examples there do not work and it looks heavily outdated, without proper documentation"* ([Elixir Forum, 2023](https://elixirforum.com/t/how-to-convert-telemetry-to-opentelemetry/58242))
- The library itself acknowledges: *"Non-library authors should use opentelemetry directly wherever possible"* ([source](https://hexdocs.pm/opentelemetry_telemetry/OpentelemetryTelemetry.html#module-limitations))

**3. Community Best Practices**
Research of production Elixir applications and official guides consistently show direct OpenTelemetry usage:
- Official OpenTelemetry Getting Started guides use direct APIs
- Framework integrations (Phoenix, Ecto, Cowboy) use OpenTelemetry directly
- Real-world blog posts and tutorials demonstrate direct usage patterns

### Sources Reviewed

- [Elixir Forum: Telemetry vs OpenTelemetry relationship](https://elixirforum.com/t/what-is-the-relationship-between-telemetry-and-opentelemetry/69068/7)
- [OpenTelemetry Telemetry Bridge Limitations](https://hexdocs.pm/opentelemetry_telemetry/OpentelemetryTelemetry.html#module-limitations)
- [Community Experience with Bridge Library](https://elixirforum.com/t/how-to-convert-telemetry-to-opentelemetry/58242)
- [Official OpenTelemetry Erlang/Elixir Documentation](https://opentelemetry.io/docs/languages/erlang/)
- Multiple production implementation examples showing direct OTel usage

### Decision Rationale

The telemetry bridge approach would have prevented us from achieving our primary goal: **end-to-end trace visibility across our distributed GenServer architecture**. Since our most critical traces (OAuth token refresh, API calls, session management) all involve multiple processes, the single-process limitation would have fragmented our observability.

Additionally, the community consensus and official recommendation point toward direct OpenTelemetry usage for application developers, reserving the telemetry bridge primarily for library authors who want to emit events without taking a direct OpenTelemetry dependency.

## Technical Details

### OpenTelemetry Wrapper Module Consideration

We evaluated whether to wrap OpenTelemetry APIs in our own abstraction layer. After careful consideration, we've decided to **start with direct OpenTelemetry usage** but will revisit this decision as patterns emerge in our codebase.

#### Why We're Not Using a Wrapper Initially

**1. Straightforward Use Case**
Our tracing needs are standard and well-supported by existing OpenTelemetry patterns:
- API calls to external services (Spotify, Setlist.fm)
- GenServer operations and lifecycle
- OAuth authentication flows
- Database queries (via `opentelemetry_ecto`)

**2. Rich Ecosystem Advantage**
OpenTelemetry already provides domain-specific instrumentation libraries that we can leverage directly:
- `opentelemetry_phoenix` for web request tracing
- `opentelemetry_ecto` for database operation tracing
- Manual HTTP client instrumentation patterns

**3. Learning Investment**
Team knowledge of OpenTelemetry APIs is transferable and valuable across projects and organizations.

**4. Community Alignment**
Research shows that even framework authors typically use OpenTelemetry APIs directly rather than creating abstraction layers.

#### When We Might Add a Wrapper Module

As we develop Setlistify's observability implementation, we should consider adding a minimal wrapper module if we observe these patterns:

**1. Repeated Domain-Specific Tracing Patterns**
```elixir
# If we find ourselves repeating this pattern frequently:
OpenTelemetry.Tracer.with_span "spotify.search_track" do
  OpenTelemetry.Tracer.set_attributes([
    {"service.name", "spotify"},
    {"operation", "search_track"},
    {"user.id", user_id}
  ])
  # business logic
end

# We might want a helper like:
Setlistify.Tracing.trace_api_call("spotify", "search_track", %{user_id: user_id}, fn ->
  # business logic
end)
```

**2. Consistent Error Handling Needs**
```elixir
# If we repeatedly need error handling with tracing:
defmodule Setlistify.Tracing do
  def trace_with_error_handling(name, fun) do
    OpenTelemetry.Tracer.with_span name do
      try do
        result = fun.()
        OpenTelemetry.Tracer.set_status(:ok)
        result
      rescue
        error ->
          OpenTelemetry.Tracer.set_status(:error, Exception.message(error))
          OpenTelemetry.Tracer.record_exception(error)
          reraise error, __STACKTRACE__
      end
    end
  end
end
```

**3. Testing Abstraction Requirements**
```elixir
# If we need to disable tracing in tests:
# config/test.exs
config :setlistify, :observability_backend, Setlistify.Observability.NoOp

defmodule Setlistify.Observability.NoOp do
  def trace_span(_name, _metadata, fun), do: fun.()
  def set_attributes(_attrs), do: :ok
end
```

**4. Semantic Convention Enforcement**
```elixir
# If we want to enforce OpenTelemetry semantic conventions:
defmodule Setlistify.Tracing do
  def set_user_context(user_id) do
    OpenTelemetry.Tracer.set_attributes([
      {"user.id", user_id},
      {"enduser.id", user_id}  # OpenTelemetry semantic convention
    ])
  end
  
  def set_api_attributes(method, url, status_code) do
    OpenTelemetry.Tracer.set_attributes([
      {"http.method", method},
      {"http.url", url}, 
      {"http.status_code", status_code}
    ])
  end
end
```

#### Principles for Future Wrapper Consideration

If we do add wrapper functions, they should:
- **Complement, not replace** direct OpenTelemetry usage
- **Be minimal helpers** rather than full abstractions
- **Follow OpenTelemetry semantic conventions**
- **Not hide the underlying OpenTelemetry APIs** from the team
- **Solve actual repeated patterns** we observe in our codebase

This approach allows us to start simple and add abstraction only when we've identified clear value from repeated patterns in our actual implementation.

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

*Configuration files for Tempo, Loki, Prometheus, and Grafana datasources remain the same as in the original spec.*

### 1. Core Libraries and Dependencies

### 4. Core Implementation Components

#### OpenTelemetry Setup and Configuration

```elixir
defmodule Setlistify.Observability do
  @moduledoc """
  Central module for setting up all observability components using OpenTelemetry directly.
  """

  def setup do
    # Set up OpenTelemetry logger metadata (Phase 2 - completed)
    OpentelemetryLoggerMetadata.setup()

    # Set up automatic framework instrumentation
    :opentelemetry_cowboy.setup()
    OpentelemetryPhoenix.setup(adapter: :cowboy2)
    # Note: OpentelemetryEcto.setup would go here if we had a database

    # Set up LiveView instrumentation (Phase 2 - completed)
    # This is handled via the LiveViewTelemetry hook in router

    # Future phases: HTTP client tracing, metrics, etc.
  end
end
```

```elixir
# This is now handled by the opentelemetry_logger_metadata package
# Configuration in config/dev.exs:

config :logger, :console,
  format: "$time [$level] $message $metadata\n",
  metadata: [:request_id, :trace_id, :span_id]

# Setup in Setlistify.Observability.setup/0:
OpentelemetryLoggerMetadata.setup()
```

#### Enhanced Logger with Trace Context (Phase 2 - Completed)

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

#### LiveView Telemetry (Phase 2 - Completed)

#### 5.1 Key Modules to Instrument

The following modules represent critical paths in Setlistify and should be instrumented with `:telemetry` events:

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

### 5. Application-Specific Instrumentation

##### Spotify API Client Instrumentation

```elixir
defmodule Setlistify.Spotify.API.ExternalClient do
  @behaviour Setlistify.Spotify.API
  require Logger
  require OpenTelemetry.Tracer

  def search_for_track(user_session, artist, track) do
    OpenTelemetry.Tracer.with_span "spotify.search_track" do
      # Set span attributes following OpenTelemetry semantic conventions
      OpenTelemetry.Tracer.set_attributes([
        {"service.name", "spotify"},
        {"spotify.operation", "search_track"},
        {"spotify.artist", artist},
        {"spotify.track", track},
        {"user.id", user_session.user_id},
        {"enduser.id", user_session.user_id}
      ])

      Logger.info("Searching for track", %{
        artist: artist,
        track: track,
        user_id: user_session.user_id
      })

      request_fn = fn req ->
        Req.get(req,
          url: "/search",
          params: %{q: "artist:#{artist} track:#{track}", type: "track"}
        )
      end

      case with_token_refresh(user_session, request_fn, "track search") do
        {:ok, %{status: 200} = resp} ->
          items = resp.body |> Map.get("tracks", %{}) |> Map.get("items", [])

          result = case List.first(items) do
            nil ->
              Logger.warning("No search results", %{artist: artist, track: track})
              OpenTelemetry.Tracer.set_attribute("spotify.results.count", 0)
              nil
            track_info ->
              Logger.info("Found match", %{artist: artist, track: track})
              OpenTelemetry.Tracer.set_attributes([
                {"spotify.results.count", length(items)},
                {"spotify.track.uri", track_info["uri"]}
              ])
              %{uri: track_info["uri"], preview_url: track_info["preview_url"]}
          end

          OpenTelemetry.Tracer.set_status(:ok)
          result

        {:error, reason} = error ->
          Logger.error("Search failed", %{
            artist: artist,
            track: track,
            error: reason
          })
          OpenTelemetry.Tracer.set_status(:error, "Search failed: #{inspect(reason)}")
          error

        other ->
          OpenTelemetry.Tracer.set_status(:error, "Unexpected response")
          other
      end
    end
  end

  defp with_token_refresh(user_session, request_fn, context) do
    OpenTelemetry.Tracer.with_span "spotify.token_refresh_wrapper" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_session.user_id},
        {"spotify.context", context}
      ])

      req = client(user_session)

      case request_fn.(req) do
        {:ok, %{status: 401} = response} ->
          OpenTelemetry.Tracer.add_event("spotify.token.expired", %{
            "user.id" => user_session.user_id,
            "context" => context
          })

          # Handle token refresh logic...
          authenticate_header = Req.Response.get_header(response, "www-authenticate")
          authenticate_value = List.first(authenticate_header) || ""

          if authenticate_header && String.contains?(authenticate_value, "invalid_token") do
            case SessionManager.refresh_session(user_session.user_id) do
              {:ok, new_session} ->
                Logger.info("Token refreshed", %{
                  user_id: user_session.user_id,
                  context: context
                })
                OpenTelemetry.Tracer.set_attribute("spotify.token.refreshed", true)
                request_fn.(client(new_session))

              {:error, reason} ->
                OpenTelemetry.Tracer.set_status(:error, "Token refresh failed: #{inspect(reason)}")
                {:error, :token_refresh_failed}
            end
          else
            {:ok, response}
          end

        other ->
          OpenTelemetry.Tracer.set_attribute("spotify.token.refreshed", false)
          other
      end
    end
  end

  def exchange_code(code, redirect_uri) do
    OpenTelemetry.Tracer.with_span "spotify.oauth.exchange_code" do
      OpenTelemetry.Tracer.set_attributes([
        {"oauth.provider", "spotify"},
        {"oauth.redirect_uri", redirect_uri}
      ])

      # OAuth code exchange implementation...
      case perform_token_exchange(code, redirect_uri) do
        {:ok, tokens} = result ->
          OpenTelemetry.Tracer.set_status(:ok)
          Logger.info("OAuth code exchange successful")
          result

        {:error, reason} = error ->
          OpenTelemetry.Tracer.set_status(:error, "OAuth exchange failed: #{inspect(reason)}")
          Logger.error("OAuth code exchange failed", %{error: reason})
          error
      end
    end
  end
end
```

##### Session Manager Instrumentation

```elixir
defmodule Setlistify.Spotify.SessionManager do
  use GenServer
  require Logger
  require OpenTelemetry.Tracer

  def create_session(user_id, tokens) do
    OpenTelemetry.Tracer.with_span "session_manager.create_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"session.operation", "create"}
      ])

      case GenServer.call(__MODULE__, {:create_session, user_id, tokens}) do
        {:ok, session} = result ->
          Logger.info("Session created", %{user_id: user_id})
          OpenTelemetry.Tracer.set_status(:ok)
          OpenTelemetry.Tracer.set_attribute("session.created", true)
          result

        {:error, reason} = error ->
          Logger.error("Session creation failed", %{user_id: user_id, error: reason})
          OpenTelemetry.Tracer.set_status(:error, "Session creation failed: #{inspect(reason)}")
          error
      end
    end
  end

  def refresh_session(user_id) do
    OpenTelemetry.Tracer.with_span "session_manager.refresh_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"user.id", user_id},
        {"session.operation", "refresh"}
      ])

      case GenServer.call(__MODULE__, {:refresh_session, user_id}) do
        {:ok, session} = result ->
          Logger.info("Session refreshed", %{user_id: user_id})
          OpenTelemetry.Tracer.set_status(:ok)
          OpenTelemetry.Tracer.set_attribute("session.refreshed", true)
          result

        {:error, reason} = error ->
          Logger.error("Session refresh failed", %{user_id: user_id, error: reason})
          OpenTelemetry.Tracer.set_status(:error, "Session refresh failed: #{inspect(reason)}")
          error
      end
    end
  end

  # GenServer callbacks can also be instrumented
  def handle_call({:create_session, user_id, tokens}, _from, state) do
    # This span will be a child of the span created in create_session/2
    OpenTelemetry.Tracer.with_span "session_manager.handle_create_session" do
      OpenTelemetry.Tracer.set_attributes([
        {"genserver.operation", "handle_call"},
        {"user.id", user_id}
      ])

      # Implementation...
      case do_create_session(user_id, tokens, state) do
        {:ok, session, new_state} ->
          OpenTelemetry.Tracer.set_attribute("session.count", map_size(new_state.sessions))
          {:reply, {:ok, session}, new_state}

        {:error, reason} = error ->
          OpenTelemetry.Tracer.set_status(:error, inspect(reason))
          {:reply, error, state}
      end
    end
  end
end
```

##### LiveView Instrumentation Enhancement

```elixir
defmodule SetlistifyWeb.SearchLive do
  use SetlistifyWeb, :live_view
  use Gettext, backend: SetlistifyWeb.Gettext

  require Logger
  require OpenTelemetry.Tracer

  def mount(_params, _session, socket) do
    # LiveView mount span is created by LiveViewTelemetry hook
    {:ok, assign(socket, setlists: [], search: search_form(%{}))}
  end

  def handle_params(params, _uri, socket) do
    OpenTelemetry.Tracer.with_span "search_live.handle_params" do
      OpenTelemetry.Tracer.set_attributes([
        {"liveview.module", "SearchLive"},
        {"liveview.function", "handle_params"},
        {"params", inspect(params)}
      ])

      search_form = search_form(params)
      search_changeset = search_form.source

      setlists = if search_changeset.valid? do
        query = Ecto.Changeset.get_field(search_changeset, :query)
        Logger.info("Performing search", %{query: query})
        
        OpenTelemetry.Tracer.set_attribute("search.query", query)
        
        # This will create a child span via the API client instrumentation
        results = Setlistify.SetlistFm.API.search(query)
        
        OpenTelemetry.Tracer.set_attribute("search.results_count", length(results))
        results
      else
        OpenTelemetry.Tracer.set_attribute("search.valid", false)
        []
      end

      OpenTelemetry.Tracer.set_status(:ok)
      {:noreply, assign(socket, search: search_form, setlists: setlists)}
    end
  end

  def handle_event("search", %{"search" => params}, socket) do
    OpenTelemetry.Tracer.with_span "search_live.handle_search_event" do
      OpenTelemetry.Tracer.set_attributes([
        {"liveview.event", "search"},
        {"search.query", params["q"] || ""},
        {"liveview.module", "SearchLive"}
      ])

      Logger.info("Search event received", %{query: params["q"]})
      
      result = {:noreply, socket |> push_patch(to: "/#{encode_query_string(params)}")}
      
      OpenTelemetry.Tracer.set_attributes([
        {"liveview.action", "redirect"},
        {"liveview.redirect_path", "/#{encode_query_string(params)}"}
      ])
      
      result
    end
  end
end
```

##### Setlist.fm API Client Instrumentation

```elixir
defmodule Setlistify.SetlistFm.API.ExternalClient do
  @behaviour Setlistify.SetlistFm.API
  require Logger
  require OpenTelemetry.Tracer

  def search(query, endpoint \\ @root_endpoint) do
    OpenTelemetry.Tracer.with_span "setlist_fm.search" do
      OpenTelemetry.Tracer.set_attributes([
        {"service.name", "setlist_fm"},
        {"setlist_fm.operation", "search"},
        {"setlist_fm.query", query},
        {"setlist_fm.endpoint", endpoint}
      ])

      Logger.info("Searching setlists", %{query: query})

      try do
        result = Req.get!(request(endpoint),
          url: "/search/setlists",
          params: %{"artistName" => query}
        )

        setlists = result.body["setlist"] || []
        mapped_results = Enum.map(setlists, &transform_setlist/1)

        OpenTelemetry.Tracer.set_attributes([
          {"setlist_fm.results.count", length(setlists)},
          {"http.status_code", 200}
        ])

        Logger.info("Setlist search completed", %{
          query: query,
          results_count: length(setlists)
        })

        OpenTelemetry.Tracer.set_status(:ok)
        mapped_results
      rescue
        error ->
          Logger.error("Setlist search error", %{
            query: query,
            error: error
          })

          OpenTelemetry.Tracer.set_status(:error, "Search failed: #{Exception.message(error)}")
          OpenTelemetry.Tracer.record_exception(error)

          # Re-raise to maintain existing error handling
          reraise error, __STACKTRACE__
      end
    end
  end

  def get_setlist(id, endpoint \\ @root_endpoint) do
    OpenTelemetry.Tracer.with_span "setlist_fm.get_setlist" do
      OpenTelemetry.Tracer.set_attributes([
        {"service.name", "setlist_fm"},
        {"setlist_fm.operation", "get_setlist"},
        {"setlist_fm.setlist_id", id},
        {"setlist_fm.endpoint", endpoint}
      ])

      try do
        resp = Req.get!(request(endpoint), url: "/setlist/#{id}")
        setlist_data = resp.body
        
        artist_name = get_in(setlist_data, ["artist", "name"])
        sets = get_in(setlist_data, ["sets", "set"]) || []
        total_songs = Enum.reduce(sets, 0, fn set, acc ->
          songs = Map.get(set, "song", [])
          acc + length(songs)
        end)

        OpenTelemetry.Tracer.set_attributes([
          {"setlist_fm.artist", artist_name},
          {"setlist_fm.sets.count", length(sets)},
          {"setlist_fm.songs.total", total_songs},
          {"http.status_code", 200}
        ])

        result = transform_single_setlist(setlist_data)

        Logger.info("Setlist fetched", %{
          setlist_id: id,
          artist: artist_name,
          total_songs: total_songs
        })

        OpenTelemetry.Tracer.set_status(:ok)
        result
      rescue
        error ->
          Logger.error("Setlist fetch error", %{
            setlist_id: id,
            error: error
          })

          OpenTelemetry.Tracer.set_status(:error, "Fetch failed: #{Exception.message(error)}")
          OpenTelemetry.Tracer.record_exception(error)

          reraise error, __STACKTRACE__
      end
    end
  end
end
```

### Function Decorator Pattern (`@trace`)

During the initial implementation phases, we experimented with a function decorator pattern that would automatically wrap functions with telemetry spans:

```elixir
defmodule MyModule do
  use Setlistify.Trace
  
  @trace
  def my_function(arg1, arg2) do
    # Function body
  end
end
```

**Why We Postponed This Approach:**

1. **Implementation Complexity**: The macro implementation proved difficult to get right, particularly around:
   - AST manipulation for function transformation
   - Preserving function metadata and documentation
   - Handling different function arities and default parameters

2. **Limited Flexibility**: The decorator pattern has inherent limitations:
   - Difficulty adding dynamic span attributes based on runtime values
   - Challenges with cross-process tracing (GenServer interfaces)
   - Limited control over span naming and metadata

3. **Community Concerns**: The Elixir community has raised valid concerns about function decorators:
   - They can make code harder to reason about
   - They hide important behavior (telemetry) from plain sight
   - They go against Elixir's philosophy of explicit, clear code
   - Reference: [Elixir Forum Discussion](https://elixirforum.com/t/nicest-way-to-emulate-function-decorators/2050/26)

4. **Testing Complications**: Decorators can complicate testing:
   - Harder to mock individual telemetry events
   - Less control over test assertions
   - Potential interference with existing Hammox mocks

**Future Consideration**: After implementing the telemetry-based approach and gaining experience with observability patterns in our application, we may revisit the decorator approach if:
- We identify specific use cases where it would add significant value
- The implementation challenges can be overcome
- We develop patterns that maintain code clarity and testability

The current `:telemetry.span/3` approach provides explicit, flexible instrumentation that aligns well with Elixir conventions and our testing strategy.

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

### Phase 1: Core OpenTelemetry Instrumentation

**Status:** NEXT UP

**Tasks:**
1. Complete OpenTelemetry dependencies in mix.exs
2. Implement Setlistify.Observability.setup/0 for framework integrations
3. Add `OpenTelemetry.Tracer.with_span/2` instrumentation to key modules:
   - `lib/setlistify/spotify/api/external_client.ex` - Add spans to all API operations
   - `lib/setlistify/setlist_fm/api/external_client.ex` - Add spans to search and get_setlist
   - `lib/setlistify/spotify/session_manager.ex` - Add spans to session lifecycle operations
   - `lib/setlistify/spotify/user_session.ex` - Add spans to token refresh and API calls
   - `lib/setlistify_web/controllers/oauth_callback_controller.ex` - Add spans to OAuth flows
4. Set span attributes following OpenTelemetry semantic conventions
5. Ensure proper error handling with `OpenTelemetry.Tracer.set_status/2` and `record_exception/1`
6. Enhance existing LiveView instrumentation with more detailed spans
7. Add context propagation for cross-process operations (GenServer calls, Tasks)
8. Create integration tests for OpenTelemetry span creation and attributes
9. Test locally with docker stack to verify end-to-end traces
10. Verify connected traces across process boundaries (HTTP → LiveView → GenServer → API calls)

**Testing Focus:**
- Integration tests for OpenTelemetry span creation and attributes
- Verify trace context propagation across GenServer boundaries
- Test error scenarios create proper error spans with exceptions
- Manual validation with local Grafana UI showing connected traces
- Performance testing to ensure acceptable overhead

**Expected Timeline:** 2-3 days
**Dependencies:** Phase 0 completion ✅, Phase 2 partial completion ✅
**Key Success Metrics:** 
- End-to-end traces visible in local Grafana showing complete OAuth flow
- Trace context properly propagated across SessionManager → UserSession → API calls
- LiveView interactions linked to business operations via spans
- Error traces include proper exception details and context

## Post-Implementation Ideas to Consider

### Phase 2: Enhanced Tracing and Logging (Local) - Complete Remaining Tasks

**Tasks Remaining:**
1. Add Loki logger configuration for local development
2. Create comprehensive HTTP client tracing with OpenTelemetry context propagation
3. Complete LiveView instrumentation for all user flows
4. Add OpenTelemetry spans for error scenarios and edge cases
5. Create structured tests for OpenTelemetry instrumentation
6. Verify log correlation with traces in local Grafana

**Testing Focus:**
- Exception handling with proper OpenTelemetry error status
- HTTP client request tracing with context propagation
- Log correlation verification in Grafana
- LiveView event flow testing with span hierarchy

**Expected Timeline:** 1-2 days
**Dependencies:** Phase 1 completion
**Key Success Metrics:** Complete observability stack with logs correlated to traces via trace context

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
