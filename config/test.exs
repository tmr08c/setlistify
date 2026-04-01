import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :setlistify, SetlistifyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "MyzOQMgQQGIwlRY163PrVylUkcOHi5Sx52W9BLxCZkqkUTURG73ChOidQruPefgm",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Configure Req to use test stubs in test environment and disable retries
config :setlistify,
  spotify_req_options: [
    plug: {Req.Test, MySpotifyStub},
    retry: false
  ],
  setlist_fm_req_options: [
    plug: {Req.Test, MySetlistFmStub},
    retry: false
  ],
  apple_music_req_options: [
    plug: {Req.Test, MyAppleMusicStub},
    retry: false
  ]

# Disable OpenTelemetry exports in test
config :opentelemetry,
  traces_exporter: :none

# Disable PromEx for tests
config :setlistify, Setlistify.PromEx,
  grafana: :disabled,
  metrics_server: :disabled

# Disable Apple Music token manager in tests (uses placeholder PEM from .env.example)
config :setlistify, start_apple_music_token_manager: false
