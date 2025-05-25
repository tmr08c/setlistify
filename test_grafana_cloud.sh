#!/bin/bash

# Test script to verify Grafana Cloud configuration

echo "🔍 Checking Grafana Cloud configuration..."
echo "============================================================"

# Source the .env file
if [ -f .env ]; then
    # Export variables from .env
    set -a
    source .env
    set +a
    echo "✅ Loaded .env file"
else
    echo "❌ .env file not found"
    exit 1
fi

# Check if Grafana Cloud variables are set
if [ -n "$GRAFANA_CLOUD_API_KEY" ]; then
    echo "✅ GRAFANA_CLOUD_API_KEY is set"
    echo "✅ GRAFANA_CLOUD_INSTANCE_ID: $GRAFANA_CLOUD_INSTANCE_ID"
    echo "✅ GRAFANA_CLOUD_REGION: ${GRAFANA_CLOUD_REGION:-us-central1}"
    
    # Show endpoint
    TEMPO_ENDPOINT="tempo-${GRAFANA_CLOUD_REGION:-us-central1}.grafana.net:443"
    echo ""
    echo "📍 Tempo endpoint: $TEMPO_ENDPOINT"
    
    # Show auth header (redacted)
    AUTH_HEADER=$(echo -n "$GRAFANA_CLOUD_INSTANCE_ID:$GRAFANA_CLOUD_API_KEY" | base64)
    REDACTED_HEADER="Basic ${AUTH_HEADER:0:10}...${AUTH_HEADER: -4}"
    echo "🔐 Auth header: $REDACTED_HEADER"
    
    echo ""
    echo "📊 Configuration looks good for Grafana Cloud!"
    echo ""
    echo "To test the actual connection, run the app with:"
    echo "  bin/server"
    echo ""
    echo "Then perform some actions and check your Grafana Cloud instance:"
    echo "  https://$GRAFANA_CLOUD_INSTANCE_ID.grafana.net"
else
    echo "❌ GRAFANA_CLOUD_API_KEY is not set"
    echo "ℹ️  The app will use local LGTM stack instead"
    echo ""
    echo "Local endpoints:"
    echo "  - Grafana UI: http://localhost:3000"
    echo "  - OTLP HTTP: http://localhost:4318"
fi

echo ""
echo "============================================================"