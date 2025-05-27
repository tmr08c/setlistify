import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/setlistify start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :setlistify, SetlistifyWeb.Endpoint, server: true
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :setlistify, SetlistifyWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :setlistify, SetlistifyWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your endpoint, ensuring
  # no data is ever sent via http, always redirecting to https:
  #
  #     config :setlistify, SetlistifyWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Grafana Cloud Loki configuration for production
  if loki_url = System.get_env("LOKI_URL") do
    config :logger,
      backends: [:console, Setlistify.LokiLogger]

    config :logger, Setlistify.LokiLogger,
      url: loki_url,
      username: System.get_env("LOKI_USERNAME"),
      password: System.get_env("LOKI_PASSWORD"),
      level: :info,
      metadata: [:request_id, :trace_id, :span_id, :user_id],
      max_buffer: 100,
      labels: %{
        "application" => "setlistify",
        "environment" => "production",
        "instance" => System.get_env("FLY_ALLOC_ID", "unknown")
      }
  end
end

# Non-prod specific configuration

# For local development, use `DotenvParser` to fetch secrets from our `.env`
# file and make them available as environmental variables.
#
# For test, we use the `.example` copy of our `.env` file. This should include
# all of the keys, but with phony values, preventing us from hitting real APIs
# in tests.
#
# Production (and production-like) environments are expected to set these value
# directly (if a default cannot be provided).
case Config.config_env() do
  :dev -> DotenvParser.load_file(".env")
  :test -> DotenvParser.load_file(".env.example")
  _ -> :ok
end

## Setlist.fm API
config :setlistify, setlist_fm_api_key: System.fetch_env!("SETLIST_FM_API_SECRET")

## Spotify API
config :setlistify, spotify_client_id: System.fetch_env!("SPOTIFY_CLIENT_ID")
config :setlistify, spotify_client_secret: System.fetch_env!("SPOTIFY_CLIENT_SECRET")

## PromEx metrics server port configuration
if prom_ex_port = System.get_env("PROM_EX_PORT") do
  config :setlistify, Setlistify.PromEx,
    port: String.to_integer(prom_ex_port),
    path: "/metrics"
end

## OpenTelemetry Configuration
# Determine if we should use Grafana Cloud based on environment variables
use_grafana_cloud = System.get_env("GRAFANA_CLOUD_API_KEY") != nil

if use_grafana_cloud do
  # Grafana Cloud configuration
  grafana_api_key = System.get_env("GRAFANA_CLOUD_API_KEY")
  grafana_region = System.get_env("GRAFANA_CLOUD_REGION", "us-central1")
  grafana_zone = System.get_env("GRAFANA_CLOUD_ZONE")

  # Construct Grafana Cloud endpoints based on region
  # Following the Silbernagel.dev example that works
  tempo_endpoint = System.get_env("GRAFANA_CLOUD_TEMPO_ENDPOINT")

  # For Basic auth, we need user_id:api_key in base64
  # Use specific user ID from Grafana Cloud Tempo configuration
  grafana_user_id = System.get_env("GRAFANA_CLOUD_USER_ID")
  otel_auth = Base.encode64("#{grafana_user_id}:#{grafana_api_key}")

  # Configure OpenTelemetry exporter following the working example
  config :opentelemetry_exporter,
    otlp_protocol: :grpc,
    otlp_traces_endpoint: tempo_endpoint,
    otlp_headers: [{"Authorization", "Basic #{otel_auth}"}]

  # Configure PromEx for Grafana Cloud metrics
  # Grafana Cloud Prometheus/Mimir configuration
  prometheus_endpoint = System.get_env("GRAFANA_CLOUD_PROMETHEUS_ENDPOINT")

  if prometheus_endpoint do
    config :setlistify, Setlistify.PromEx,
      manual_metrics_start_delay: :no_delay,
      drop_metrics_groups: [],
      grafana_agent: [
        version: "0.42.0",
        working_directory: "/tmp/prom_ex",
        config_opts: [
          # Local metrics server config
          metrics_server_path: "/metrics",
          metrics_server_port: 9568,
          metrics_server_scheme: "http",
          metrics_server_host: "localhost",

          # Grafana Cloud remote write config
          prometheus_url: prometheus_endpoint,
          prometheus_username: grafana_user_id,
          prometheus_password: grafana_api_key,

          # Instance identification
          instance: System.get_env("FLY_APP_NAME") || "setlistify",
          job: "setlistify",
          agent_port: 12345,
          scrape_interval: "15s"
        ]
      ]
  end

  # Add zone to resource attributes if provided
  # TODO: Should this actually be from Fly
  zone_attrs = if grafana_zone, do: [{"cloud.zone", grafana_zone}], else: []

  config :opentelemetry, :resource,
    service: [
      name: "setlistify",
      namespace: "setlistify",
      version: "1.0.0"
    ],
    deployment: [
      environment: config_env() |> to_string()
    ],
    host: [
      name: System.get_env("FLY_ALLOC_ID", "local")
    ],
    telemetry: [
      sdk: [
        name: "opentelemetry",
        language: "elixir"
      ]
    ],
    cloud:
      [
        provider: "grafana",
        region: grafana_region
      ] ++ zone_attrs
else
  # Local OTEL-LGTM configuration (default)
  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf,
    otlp_traces_endpoint: "http://localhost:4318/v1/traces",
    otlp_headers: []

  config :opentelemetry, :resource,
    service: [
      name: "setlistify",
      namespace: "setlistify",
      version: "1.0.0"
    ],
    deployment: [
      environment: config_env() |> to_string()
    ],
    host: [
      name: System.get_env("HOSTNAME", "localhost")
    ]
end
