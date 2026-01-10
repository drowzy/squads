import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :squads, Squads.Repo,
  database: Path.expand("../squads_test.db", __DIR__),
  pool_size: 1,
  pool: Ecto.Adapters.SQL.Sandbox,
  socket_options: [:raw],
  timeout: 120_000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :squads, SquadsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "AVavXbwu8FqbkDESIaWv8b13hQzCWyAauwZ9Kc/7W2Z26qJaX1qSap9gRNKw5TAY",
  server: false

# In test we don't send emails
config :squads, Squads.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :squads, :opencode_client, Squads.OpenCode.ClientMock
config :squads, :github_client, Squads.GitHub.ClientMock
