#!/bin/bash
# Script to add or update a Prometheus target dynamically

set -e

PORT="${1:-9568}"
INSTANCE="${2:-default}"
TARGETS_FILE="./targets/setlistify.json"

if [ -z "$1" ]; then
    echo "Usage: $0 <port> [instance_name]"
    echo "Example: $0 9569 instance2"
    echo ""
    echo "This will add host.docker.internal:9569 with label instance=instance2"
    exit 1
fi

# Ensure targets directory exists
mkdir -p ./targets

# Read existing targets or create empty array
if [ -f "$TARGETS_FILE" ]; then
    CURRENT=$(cat "$TARGETS_FILE")
else
    CURRENT="[]"
fi

# Add or update the target using jq
echo "$CURRENT" | jq --arg port "$PORT" --arg instance "$INSTANCE" '
  # Remove any existing entry for this instance
  map(select(.labels.instance != $instance)) +
  # Add the new entry
  [{
    "targets": ["host.docker.internal:" + $port],
    "labels": {
      "instance": $instance
    }
  }]
' > "$TARGETS_FILE"

echo "✅ Target updated!"
echo "   Instance: $INSTANCE"
echo "   Port: $PORT"
echo ""
echo "Current targets:"
jq -r '.[] | "  - Instance: " + .labels.instance + " -> " + .targets[0]' "$TARGETS_FILE"

if [ -n "$PROMETHEUS_CONTAINER" ]; then
    echo ""
    echo "Note: Prometheus will automatically pick up the changes within 10 seconds."
fi