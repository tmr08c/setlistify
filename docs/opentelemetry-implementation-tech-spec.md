# OpenTelemetry Implementation Tech Spec

## Executive Summary

This document outlines the implementation of OpenTelemetry in our Elixir/Phoenix/LiveView application. OpenTelemetry will provide comprehensive observability through traces, logs, and metrics, with Grafana Cloud as our backend provider. This implementation will be rolled out in phases, prioritizing tracing capabilities, followed by log correlation and metrics.

## Background

Our application is built with Elixir, Phoenix, and LiveView. It currently does not use a database and is deployed to Fly.io. Our primary observability needs are:

1. Tracing user flows, particularly the OAuth session manager's token refresh operations
2. Tracking exceptions and errors across the system
3. Monitoring API calls to external services
4. Correlating logs with traces
5. Collecting basic application metrics

## Technical Approach

After evaluating several options, we've decided to:

1. Use `:telemetry` as an abstraction layer for most of our instrumentation
2. Leverage `opentelemetry_telemetry` to bridge telemetry events to OpenTelemetry spans
3. Implement the `@trace` decorator pattern for function-level tracing
4. Add trace context propagation to HTTP requests via Req
5. Include structured logging with trace context
6. Send all telemetry data to Grafana Cloud

This approach provides flexibility in changing backends while maintaining a clean instrumentation layer in our application code.

## Options Considered

### Instrumentation Approach

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Direct OpenTelemetry API | Better cross-process context propagation, Full feature access | Tighter coupling to OpenTelemetry | Rejected |
| `:telemetry` Abstraction | Decoupled from specific backends, Phoenix ecosystem standard | Process boundary limitations, More complex setup | **Selected** |
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
    
    # Telemetry
    {:telemetry, "~> 1.2.1"},
    {:telemetry_metrics, "~> 0.6.1"},
    
    # Logging
    {:loki_logger, "~> 0.3.0"}
  ]
end
```

### 2. Configuration

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
      name: "my_app",
      namespace: "my_namespace",
      version: Mix.Project.config()[:version] || "dev"
    ],
    deployment: [
      environment: System.get_env("FLY_APP_ENVIRONMENT", "development")
    ],
    host: [
      name: System.get_env("FLY_ALLOC_ID", "local")
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

### 3. Core Implementation Components

#### Trace Decorator Module

```elixir
defmodule MyApp.Trace do
  @moduledoc """
  Provides function decoration for automatic OpenTelemetry tracing.
  
  Usage:
      defmodule MyModule do
        use MyApp.Trace
        
        @trace
        def my_function(arg1, arg2) do
          # Function body
        end
      end
  """
  
  defmacro __using__(_opts) do
    quote do
      import MyApp.Trace, only: [trace: 1]
      Module.register_attribute(__MODULE__, :traced_functions, accumulate: true)
      @before_compile MyApp.Trace
    end
  end
  
  defmacro __before_compile__(env) do
    traced_functions = Module.get_attribute(env.module, :traced_functions)
    
    # Register these functions in the telemetry registry if one exists
    if function_exported?(MyApp.TelemetryEvents, :register_functions, 2) do
      for {name, arity} <- traced_functions do
        MyApp.TelemetryEvents.register_functions(env.module, name)
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

```elixir
defmodule MyApp.StructuredLogger do
  @moduledoc """
  Provides structured logging with OpenTelemetry trace context.
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
  
  @doc """
  Log at info level with structured metadata.
  """
  defmacro info(message, metadata \\ []) do
    quote do
      require Logger
      Logger.info(unquote(message), unquote(metadata))
    end
  end
  
  @doc """
  Log at error level with structured metadata and automatic exception handling.
  """
  defmacro error(message, metadata \\ []) do
    quote do
      require Logger
      metadata = unquote(metadata)
      
      # If this is in a rescue block, try to extract exception info
      metadata = cond do
        Map.has_key?(metadata, :error) -> metadata
        Process.get(:current_stacktrace) != nil ->
          Map.merge(metadata, %{
            error: Process.get(:current_exception),
            stacktrace: Process.get(:current_stacktrace)
          })
        true -> metadata
      end
      
      Logger.error(unquote(message), metadata)
    end
  end
  
  # Add similar macros for debug, warn
end
```

#### HTTP Client with Trace Propagation

```elixir
defmodule MyApp.TracedReq do
  @moduledoc """
  Provides a Req plugin that adds OpenTelemetry trace propagation
  and instrumentation to all HTTP requests.
  """
  
  def attach do
    # Register the plugin with req
    Req.update([
      plugins: [
        {MyApp.TracedReq.Plugin, []}
      ]
    ])
  end
  
  defmodule Plugin do
    @moduledoc false
    
    @behaviour Req.Request.Plugin
    
    @impl true
    def init(request, options) do
      # Replace this with your service names map if needed
      service_names = %{
        "example.com" => "example-api",
        "api.github.com" => "github-api"
        # Add more service mappings as needed
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
defmodule MyApp.TelemetryEvents do
  @moduledoc """
  Registry of telemetry events for the application.
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
  
  # Register events for authentication
  register :auth_login_start, [:my_app, :auth, :login, :start], 
    "Emitted when a user login attempt begins"
    
  register :auth_login_stop, [:my_app, :auth, :login, :stop],
    "Emitted when a user login attempt completes"
    
  register :auth_login_exception, [:my_app, :auth, :login, :exception],
    "Emitted when a user login attempt fails with an exception"
    
  register :auth_token_refresh_start, [:my_app, :auth, :token_refresh, :start],
    "Emitted when an OAuth token refresh begins"
    
  register :auth_token_refresh_stop, [:my_app, :auth, :token_refresh, :stop],
    "Emitted when an OAuth token refresh completes"
    
  register :auth_token_refresh_exception, [:my_app, :auth, :token_refresh, :exception],
    "Emitted when an OAuth token refresh fails with an exception"
  
  # Add more event registrations as needed
  
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

#### Telemetry Setup

```elixir
defmodule MyApp.Telemetry do
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
      
      # Authentication Metrics
      counter("my_app.auth.token_refresh.count", tags: [:status]),
      distribution("my_app.auth.token_refresh.duration",
        unit: {:native, :millisecond},
        tags: [:status]
      ),
      
      # API Client Metrics
      counter("my_app.api_client.request.count", 
        tags: [:service, :endpoint, :status]
      ),
      distribution("my_app.api_client.request.duration",
        unit: {:native, :millisecond},
        tags: [:service, :endpoint, :status]
      ),
      
      # Error Metrics
      counter("my_app.error.count", 
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
defmodule MyApp.Observability do
  @moduledoc """
  Central module for setting up all observability components.
  """
  
  def setup do
    # Set up OpenTelemetry handlers for telemetry events
    setup_telemetry_handlers()
    
    # Set up structured logging
    MyApp.StructuredLogger.setup()
    
    # Set up Req with trace propagation
    MyApp.TracedReq.attach()
    
    # Set up telemetry metrics
    MyApp.Telemetry.start_link([])
    
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

### 4. Sample Usage

```elixir
defmodule MyApp.UserService do
  use MyApp.Trace
  alias MyApp.StructuredLogger, as: Logger
  
  @trace
  def authenticate_user(username, password) do
    Logger.info("Authenticating user", %{username: username})
    
    # Implementation...
    result = check_credentials(username, password)
    
    if result do
      Logger.info("User authenticated successfully", %{username: username})
    else
      Logger.error("Authentication failed", %{username: username})
    end
    
    result
  end
  
  @trace
  def refresh_token(user_id) do
    Logger.info("Refreshing token", %{user_id: user_id})
    
    try do
      # Make API request using the traced Req client
      response = MyApp.TracedReq.post(
        "https://oauth.example.com/token",
        %{user_id: user_id},
        headers: [{"Content-Type", "application/json"}]
      )
      
      case response do
        %{status: 200, body: body} ->
          Logger.info("Token refreshed successfully", %{user_id: user_id})
          {:ok, body}
          
        %{status: status} ->
          Logger.error("Token refresh failed", %{
            user_id: user_id,
            status: status
          })
          {:error, "HTTP Error #{status}"}
      end
    rescue
      e ->
        Logger.error("Token refresh exception", %{
          user_id: user_id,
          error: e,
          stacktrace: __STACKTRACE__
        })
        {:error, "Exception: #{Exception.message(e)}"}
    end
  end
  
  defp check_credentials(username, password) do
    # Implementation...
  end
end
```

## Deployment Configuration

For Fly.io deployment, add the following to your deployment process:

```bash
# Set Grafana Cloud credentials
fly secrets set GRAFANA_API_KEY=your_api_key
fly secrets set GRAFANA_ORG=your_org_name

# Set Loki URL for logs
fly secrets set LOKI_URL=https://logs-prod-us-central1.grafana.net/loki/api/v1/push

# Set OpenTelemetry resource attributes to include Fly.io information
fly secrets set OTEL_RESOURCE_ATTRIBUTES=service.name=${FLY_APP_NAME},service.instance.id=${FLY_ALLOC_ID},cloud.provider=fly_io,cloud.region.id=${FLY_REGION}
```

## Implementation Plan

### Phase 1: Core Tracing Infrastructure

**Tasks:**
1. Add OpenTelemetry dependencies to project
2. Create basic configuration for Grafana Cloud 
3. Implement Trace decorator module
4. Set up telemetry handlers for framework events
5. Add initial instrumentation to critical flows (OAuth token refresh)
6. Deploy to Fly.io with basic tracing enabled
7. Verify trace data is flowing to Grafana Cloud

**Expected Timeline:** 1-2 days
**Dependencies:** None

### Phase 2: Enhanced Tracing and Logging

**Tasks:**
1. Implement structured logging with trace context correlation
2. Add Loki logger configuration
3. Create exception tracking system
4. Implement HTTP client tracing with Req
5. Create telemetry event registry
6. Add telemetry events for key business operations
7. Verify log correlation is working in Grafana Cloud

**Expected Timeline:** 2-3 days
**Dependencies:** Phase 1 completion

### Phase 3: Metrics and Dashboards

**Tasks:**
1. Implement telemetry metrics collection
2. Set up metrics reporting to Grafana Cloud
3. Create initial Grafana dashboards for:
   - Application health overview
   - API performance metrics
   - Error rates and exceptions
   - OAuth token refresh monitoring
4. Set up VM and process metrics
5. Test and validate metrics flow

**Expected Timeline:** 1-2 days
**Dependencies:** Phase 2 completion

### Phase 4: Optimization and Refinement

**Tasks:**
1. Analyze performance impact of instrumentation
2. Optimize span creation and attribute collection
3. Implement sampling strategy if needed
4. Refine dashboards based on actual usage
5. Document the observability system
6. Create runbook for common observability tasks

**Expected Timeline:** 1-2 days
**Dependencies:** Phase 3 completion

## Maintenance Considerations

1. **Version Updates**: Regular updates to OpenTelemetry libraries
2. **Data Volume**: Monitor data usage in Grafana Cloud free tier
3. **Performance Impact**: Assess any performance impact of instrumentation
4. **Dashboard Maintenance**: Keep dashboards updated as application evolves

## Success Criteria

1. Complete trace visibility of OAuth token refresh process
2. Automatic error tracking across the application
3. Log correlation with trace context
4. Basic metrics collection for application performance
5. Clear dashboards in Grafana Cloud for monitoring

## Conclusion

This implementation will provide comprehensive observability for our Elixir/Phoenix application, with a focus on tracing capabilities. By using `:telemetry` as an abstraction layer and sending data to Grafana Cloud, we maintain flexibility while leveraging powerful observability tools. The phased approach allows for incremental deployment and validation, ensuring that each component is working correctly before proceeding to the next phase.
