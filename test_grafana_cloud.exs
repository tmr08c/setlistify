#!/usr/bin/env elixir
# Test script to verify Grafana Cloud connectivity

# Load environment variables
case DotenvParser.load_file(".env") do
  :ok -> :ok
  {:error, reason} -> 
    IO.puts("Error loading .env file: #{inspect(reason)}")
    System.halt(1)
end

# Check if Grafana Cloud variables are set
grafana_api_key = System.get_env("GRAFANA_CLOUD_API_KEY")
grafana_instance_id = System.get_env("GRAFANA_CLOUD_INSTANCE_ID")
grafana_region = System.get_env("GRAFANA_CLOUD_REGION", "us-central1")

IO.puts("🔍 Checking Grafana Cloud configuration...")
IO.puts("=" <> String.duplicate("=", 60))

if grafana_api_key do
  IO.puts("✅ GRAFANA_CLOUD_API_KEY is set")
  IO.puts("✅ GRAFANA_CLOUD_INSTANCE_ID: #{grafana_instance_id}")
  IO.puts("✅ GRAFANA_CLOUD_REGION: #{grafana_region}")
  
  # Construct endpoint
  tempo_endpoint = "tempo-#{grafana_region}.grafana.net:443"
  IO.puts("\n📍 Tempo endpoint: #{tempo_endpoint}")
  
  # Show auth header (redacted)
  auth_header = "Basic " <> Base.encode64("#{grafana_instance_id}:#{grafana_api_key}")
  redacted_header = "Basic " <> String.slice(auth_header, 6, 10) <> "..." <> String.slice(auth_header, -4, 4)
  IO.puts("🔐 Auth header: #{redacted_header}")
  
  IO.puts("\n📊 Configuration looks good for Grafana Cloud!")
  IO.puts("\nTo test the actual connection, run the app with:")
  IO.puts("  bin/server")
  IO.puts("\nThen perform some actions and check your Grafana Cloud instance:")
  IO.puts("  https://#{grafana_instance_id}.grafana.net")
else
  IO.puts("❌ GRAFANA_CLOUD_API_KEY is not set")
  IO.puts("ℹ️  The app will use local LGTM stack instead")
  IO.puts("\nLocal endpoints:")
  IO.puts("  - Grafana UI: http://localhost:3000")
  IO.puts("  - OTLP HTTP: http://localhost:4318")
end

IO.puts("\n" <> String.duplicate("=", 60))