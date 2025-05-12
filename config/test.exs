import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :setlistify, SetlistifyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "MyzOQMgQQGIwlRY163PrVylUkcOHi5Sx52W9BLxCZkqkUTURG73ChOidQruPefgm",
  server: false

# In test we don't send emails.
config :setlistify, Setlistify.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

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
  ]
