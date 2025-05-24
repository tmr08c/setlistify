# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configures the endpoint
config :setlistify, SetlistifyWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: SetlistifyWeb.ErrorHTML, json: SetlistifyWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Setlistify.PubSub,
  live_view: [signing_salt: "8A8eHyXo"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.14.41",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  setlistify: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# PromEx configuration
config :setlistify, Setlistify.PromEx,
  # If you have an externally hosted Prometheus comment out this line
  # and configure the metrics_server config settings as necessary
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: [
    port: 9568,
    path: "/metrics"
  ]

# OpenTelemetry default configuration
config :opentelemetry,
  # Default to no exporter (tests)
  traces_exporter: :none

# This will be overridden in dev/prod
config :opentelemetry, :resource,
  service: [
    name: "setlistify",
    namespace: "setlistify"
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
