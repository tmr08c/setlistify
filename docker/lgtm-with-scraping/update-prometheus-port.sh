#!/bin/bash
# Script to dynamically update Prometheus scrape target port

set -e

# Default values
PROMETHEUS_CONTAINER="${PROMETHEUS_CONTAINER:-prometheus}"
NEW_PORT="${1:-9568}"
PROMETHEUS_CONFIG="/etc/prometheus/prometheus.yml"

if [ -z "$1" ]; then
    echo "Usage: $0 <port>"
    echo "Example: $0 9569"
    exit 1
fi

echo "Updating Prometheus to scrape port $NEW_PORT..."

# Create a temporary config file with the new port
docker exec $PROMETHEUS_CONTAINER sh -c "
    sed 's/host.docker.internal:[0-9]*/host.docker.internal:$NEW_PORT/g' $PROMETHEUS_CONFIG > /tmp/prometheus.yml.new &&
    mv /tmp/prometheus.yml.new $PROMETHEUS_CONFIG
"

# Reload Prometheus configuration
echo "Reloading Prometheus configuration..."
docker exec $PROMETHEUS_CONTAINER sh -c "
    wget -q --post-data='' -O - http://localhost:9090/-/reload || curl -X POST http://localhost:9090/-/reload
"

echo "✅ Prometheus configuration updated!"
echo "   Now scraping from host.docker.internal:$NEW_PORT"