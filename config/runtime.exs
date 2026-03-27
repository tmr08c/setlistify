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

## Apple Music API
config :setlistify, apple_music_team_id: System.fetch_env!("APPLE_MUSIC_TEAM_ID")
config :setlistify, apple_music_key_id: System.fetch_env!("APPLE_MUSIC_KEY_ID")
config :setlistify, apple_music_private_key: System.fetch_env!("APPLE_MUSIC_PRIVATE_KEY")

## PromEx metrics server port configuration
if prom_ex_port = System.get_env("PROM_EX_PORT") do
  config :setlistify, Setlistify.PromEx,
    port: String.to_integer(prom_ex_port),
    path: "/metrics"
end

## OpenTelemetry Configuration
# Determine if we should use Grafana Cloud based on environment variables
use_grafana_cloud = System.get_env("GRAFANA_CLOUD_API_KEY") != nil

# Grafana Cloud configuration
if use_grafana_cloud do
  grafana_api_key = System.get_env("GRAFANA_CLOUD_API_KEY")
  grafana_region = System.get_env("GRAFANA_CLOUD_REGION", "us-central1")
  grafana_zone = System.get_env("GRAFANA_CLOUD_ZONE")

  # OpenTelemetry / Tempo
  tempo_endpoint = System.get_env("GRAFANA_CLOUD_TEMPO_ENDPOINT")
  grafana_tempo_user_id = System.get_env("GRAFANA_CLOUD_TEMPO_USER_ID")
  otel_auth = Base.encode64("#{grafana_tempo_user_id}:#{grafana_api_key}")

  config :opentelemetry_exporter,
    otlp_protocol: :grpc,
    otlp_traces_endpoint: tempo_endpoint,
    otlp_headers: [{"Authorization", "Basic #{otel_auth}"}]

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

  # Metrics / Prometheus

  prometheus_endpoint = System.get_env("GRAFANA_CLOUD_PROMETHEUS_ENDPOINT")

  if prometheus_endpoint do
    prometheus_username = System.get_env("GRAFANA_CLOUD_PROMETHEUS_USERNAME")

    # Build the base PromEx configuration
    prom_ex_config = [
      manual_metrics_start_delay: :no_delay,
      drop_metrics_groups: [],
      metrics_server: [
        port: String.to_integer(System.get_env("PROM_EX_PORT", "9568")),
        path: "/metrics"
      ],
      grafana_agent: [
        working_directory: "/tmp/prom_ex",
        config_opts: [
          # Local metrics server config
          metrics_server_path: "/metrics",
          metrics_server_port: String.to_integer(System.get_env("PROM_EX_PORT", "9568")),
          metrics_server_scheme: "http",
          metrics_server_host: "localhost",

          # Grafana Cloud remote write config
          prometheus_url: prometheus_endpoint,
          prometheus_username: prometheus_username,
          prometheus_password: grafana_api_key,

          # Instance identification
          instance: System.get_env("FLY_APP_NAME") || "setlistify",
          job: "setlistify",
          scrape_interval: "15s"
        ]
      ]
    ]

    # Add Grafana dashboard configuration with dedicated dashboard API key
    # Prefer dedicated dashboard key (service account) over the OTLP key
    grafana_dashboard_key = System.get_env("GRAFANA_DASHBOARD_API_KEY")
    grafana_host = System.get_env("GRAFANA_HOST")

    prom_ex_config =
      if grafana_dashboard_key && grafana_host do
        Keyword.put(prom_ex_config, :grafana,
          host: grafana_host,
          # Use dashboard key with Editor permissions
          auth_token: grafana_dashboard_key,
          upload_dashboards_on_start: true,
          folder_name: "Setlistify Dashboards",
          annotate_app_lifecycle: true
        )
      else
        prom_ex_config
      end

    config :setlistify, Setlistify.PromEx, prom_ex_config
  end

  # Logs / Loki
  loki_endpoint = System.get_env("GRAFANA_CLOUD_LOKI_ENDPOINT")
  loki_user_id = System.get_env("GRAFANA_CLOUD_LOKI_USER_ID")

  if loki_endpoint && loki_user_id do
    config :logger, backends: [:console, Setlistify.LokiLogger]

    config :logger, Setlistify.LokiLogger,
      url: loki_endpoint,
      username: loki_user_id,
      password: grafana_api_key,
      level: :info,
      metadata: [:request_id, :trace_id, :span_id, :user_id],
      max_buffer: 100,
      labels: %{
        "application" => "setlistify",
        "environment" => config_env(),
        "instance" => System.get_env("FLY_ALLOC_ID", "unknown"),
        "fly_app" => System.get_env("FLY_APP_NAME", "setlistify"),
        "fly_region" => System.get_env("FLY_REGION", "unknown")
      }
  end

  # Local OTEL-LGTM configuration (default)
else
  # OpenTelemetry / Tempo
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

  # Local PromEx configuration (skip for test environment)
  if config_env() != :test do
    config :setlistify, Setlistify.PromEx,
      manual_metrics_start_delay: :no_delay,
      drop_metrics_groups: [],
      grafana: [
        host: "http://localhost:3000",
        auth_token: "admin:admin",
        upload_dashboards_on_start: true,
        folder_name: "Setlistify Dashboards",
        annotate_app_lifecycle: true
      ],
      metrics_server: [
        port: String.to_integer(System.get_env("PROM_EX_PORT", "9568")),
        path: "/metrics"
      ]
  end

  # Local Loki configuration
  config :logger, Setlistify.LokiLogger,
    url: "http://localhost:3100/loki/api/v1/push",
    level: :info,
    metadata: [:request_id, :trace_id, :span_id, :user_id],
    max_buffer: 50,
    labels: %{
      "application" => "setlistify",
      "environment" => "development"
    }
end
