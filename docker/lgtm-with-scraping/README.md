# LGTM Stack with Prometheus Scraping

This directory contains a Docker Compose setup for the LGTM (Loki, Grafana, Tempo, Mimir) observability stack with additional Prometheus scraping configuration for PromEx metrics.

## Configuration

### Default Port
By default, Prometheus is configured to scrape metrics from `host.docker.internal:9568`.

## Dynamic Configuration (Recommended)

### Option 1: File-Based Service Discovery

Use `prometheus-config-dynamic.yaml` which supports dynamic target updates:

1. Use the dynamic config when starting Prometheus:
   ```yaml
   # In your docker-compose.yml
   prometheus:
     volumes:
       - ./prometheus-config-dynamic.yaml:/etc/prometheus/prometheus.yml
       - ./targets:/etc/prometheus/targets
   ```

2. Add or update targets dynamically:
   ```bash
   # Add default instance on port 9568
   ./add-prometheus-target.sh 9568 default
   
   # Add another instance on port 9569
   ./add-prometheus-target.sh 9569 dev-instance
   
   # Update the default instance to port 9570
   ./add-prometheus-target.sh 9570 default
   ```

3. Prometheus automatically picks up changes within 10 seconds!

### Option 2: Hot Reload with Script

If your Prometheus container is already running with `--web.enable-lifecycle`:

```bash
# Update to scrape from port 9569
./update-prometheus-port.sh 9569
```

This modifies the config inside the container and triggers a reload.

### Using a Custom PromEx Port

If you're running Setlistify with a custom `PROM_EX_PORT`, you need to update the Prometheus configuration:

1. Copy the prometheus config:
   ```bash
   cp prometheus-config.yaml prometheus-config-custom.yaml
   ```

2. Edit `prometheus-config-custom.yaml` and update the port:
   ```yaml
   static_configs:
     - targets: ['host.docker.internal:YOUR_PORT_HERE']
   ```

3. Create a `docker-compose.override.yml`:
   ```bash
   cp docker-compose.override.example.yml docker-compose.override.yml
   ```

4. Start the stack:
   ```bash
   docker compose up -d
   ```

### Running Multiple Instances

When running multiple Setlistify instances with different ports:

```bash
# Instance 1 (default)
mix phx.server

# Instance 2 (custom port)
PROM_EX_PORT=9569 mix phx.server
```

You can configure Prometheus to scrape both:

```yaml
scrape_configs:
  - job_name: 'setlistify-default'
    static_configs:
      - targets: ['host.docker.internal:9568']
  
  - job_name: 'setlistify-instance-2'
    static_configs:
      - targets: ['host.docker.internal:9569']
```