# OpenTelemetry Phase 0: Local Development Stack Setup

This guide walks through setting up the local OpenTelemetry development environment for Setlistify.

## Prerequisites

- Docker and Docker Compose installed
- Elixir/Phoenix development environment set up
- Setlistify project initialized with `bin/init`

## Steps

### 1. Install Dependencies

First, fetch the new OpenTelemetry dependencies:

```bash
mix deps.get
```

### 2. Start the Docker Stack

Start the local Grafana stack:

```bash
./bin/otel-local start
```

This will start:
- Grafana (UI) on http://localhost:3000
- Tempo (traces) on http://localhost:3200
- Loki (logs) on http://localhost:3100 (integration will be added in Phase 2)
- Prometheus (metrics) on http://localhost:9090

### 3. Start the Phoenix Server

In a new terminal, start the Phoenix server:

```bash
bin/server
```

You should see a log message: "OpenTelemetry initialized for local development"

### 4. Test the Setup

In the IEx console that opens with the server, run:

```elixir
# Send a single test trace
OtelTest.trace()

# Send multiple traces
OtelTest.multiple_traces(5)
```

### 5. View Traces in Grafana

1. Open http://localhost:3000 in your browser
2. Click on "Explore" in the left sidebar
3. Select "Tempo" as the data source
4. Click "Search" to see recent traces
5. You should see traces with the service name "setlistify"

### 6. View the Dashboard

1. Click on "Dashboards" in the left sidebar
2. Open the "Setlistify" folder
3. Click on "Traces Overview"
4. You should see your test traces and a service map

## Verification

To verify everything is working:

1. Check that all containers are running:
   ```bash
   ./bin/otel-local status
   ```

2. Test trace connectivity:
   ```bash
   curl http://localhost:3200/ready
   ```

3. Test Loki connectivity:
   ```bash
   curl http://localhost:3100/ready
   ```

4. Send a test trace and verify it appears in Grafana within 30 seconds

## Troubleshooting

If traces aren't appearing:

1. Check Docker logs:
   ```bash
   ./bin/otel-local logs
   ```

2. Verify the Phoenix app is configured correctly:
   ```elixir
   # In IEx
   Application.get_env(:opentelemetry, :processors)
   ```

3. Reset the stack if needed:
   ```bash
   ./bin/otel-local reset
   ./bin/otel-local start
   ```

## Next Steps

Once Phase 0 is complete, proceed to Phase 1: Core Tracing Infrastructure to implement the trace decorator and instrument key modules.