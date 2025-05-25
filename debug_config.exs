#!/usr/bin/env elixir

# Debug script to verify OpenTelemetry configuration
Mix.install([
  {:dotenv_parser, "~> 2.0"}
])

# Load environment variables
DotenvParser.load_file(".env")

use_grafana_cloud = System.get_env("GRAFANA_CLOUD_API_KEY") != nil

IO.puts("🔍 Configuration Debug")
IO.puts("=" <> String.duplicate("=", 50))

IO.puts("Environment: #{Mix.env()}")
IO.puts("Using Grafana Cloud: #{use_grafana_cloud}")

if use_grafana_cloud do
  grafana_api_key = System.get_env("GRAFANA_CLOUD_API_KEY")
  grafana_instance_id = System.get_env("GRAFANA_CLOUD_INSTANCE_ID")
  grafana_user_id = System.get_env("GRAFANA_CLOUD_USER_ID", "1219955")
  grafana_region = System.get_env("GRAFANA_CLOUD_REGION", "us-central1")
  
  tempo_endpoint = "tempo-prod-26-prod-#{grafana_region}.grafana.net"
  auth_header = "Basic " <> Base.encode64("#{grafana_user_id}:#{grafana_api_key}")
  
  IO.puts("\n📍 Grafana Cloud Configuration:")
  IO.puts("  Instance ID: #{grafana_instance_id}")
  IO.puts("  User ID: #{grafana_user_id}")
  IO.puts("  Region: #{grafana_region}")
  IO.puts("  Tempo endpoint: #{tempo_endpoint}")
  IO.puts("  Auth header: Basic #{String.slice(auth_header, 6, 10)}...#{String.slice(auth_header, -4, 4)}")
  
  # Test if we can resolve the endpoint
  case :inet.gethostbyname(String.to_charlist("tempo-prod-26-prod-#{grafana_region}.grafana.net")) do
    {:ok, _} -> IO.puts("  ✅ DNS resolution successful")
    {:error, reason} -> IO.puts("  ❌ DNS resolution failed: #{reason}")
  end
else
  IO.puts("\n📍 Local Configuration:")
  IO.puts("  OTLP endpoint: http://localhost:4318/v1/traces")
end

IO.puts("\n🔧 Environment Variables:")
IO.puts("  GRAFANA_CLOUD_API_KEY: #{if System.get_env("GRAFANA_CLOUD_API_KEY"), do: "✅ Set", else: "❌ Not set"}")
IO.puts("  GRAFANA_CLOUD_INSTANCE_ID: #{System.get_env("GRAFANA_CLOUD_INSTANCE_ID") || "❌ Not set"}")
IO.puts("  GRAFANA_CLOUD_REGION: #{System.get_env("GRAFANA_CLOUD_REGION") || "❌ Not set"}")