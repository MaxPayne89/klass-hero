import Config

alias KlassHero.Messaging.Adapters.Driven.ResendEmailContentAdapter
alias KlassHero.Shared.Adapters.Driven.Events.TestEventPublisher
alias KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher
alias KlassHero.Shared.Adapters.Driven.FeatureFlags.StubFeatureFlagsAdapter
alias KlassHero.Shared.Adapters.Driven.Storage.StubStorageAdapter
alias Swoosh.Adapters.Test

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Disable fun_with_flags PubSub notifications in tests
config :fun_with_flags, :cache_bust_notifications, enabled: false

config :klass_hero, KlassHero.Mailer, adapter: Test

config :klass_hero, KlassHero.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "klass_hero_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We run a server during test for Wallaby E2E browser tests
config :klass_hero, KlassHeroWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "gY/oKuAYeC5ExhHrtu1JBwrpQdoGwtPOo3X9GdS7CFOnLe0eqRQ9w4cyV1MqvoYc",
  server: true

# Oban runs inline in tests so critical event handlers execute synchronously
config :klass_hero, Oban, testing: :inline

# Use test event publishers for testing
config :klass_hero, :event_publisher,
  module: TestEventPublisher,
  pubsub: KlassHero.PubSub

config :klass_hero, :feature_flags, adapter: StubFeatureFlagsAdapter

config :klass_hero, :integration_event_publisher,
  module: TestIntegrationEventPublisher,
  pubsub: KlassHero.PubSub

config :klass_hero, :resend_req_options,
  plug: {Req.Test, ResendEmailContentAdapter},
  retry: false

config :klass_hero, :storage,
  adapter: StubStorageAdapter,
  bucket: "klass-hero-test"

config :klass_hero, :verify_webhook_signature, false
config :klass_hero, env: :test

# Enable Ecto sandbox plug for Wallaby browser sessions
# Why: that query runs outside the Ecto test sandbox, poisoning the connection pool
# Trigger: VerifiedProviders GenServer bootstraps a DB query at app startup

# Outcome: disabling projections prevents sandbox leaks across async tests
config :klass_hero, sql_sandbox: true
config :klass_hero, start_projections: false

# Print only warnings and errors during test
config :logger, level: :warning

# OpenTelemetry: disable exporting in tests; tracing tests opt in via TracingHelpers.
# Sampler must be always_on so tracing tests receive every span deterministically.
config :opentelemetry,
  traces_exporter: :none,
  sampler: :always_on

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix_test, :endpoint, KlassHeroWeb.Endpoint

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Wallaby E2E test configuration
config :wallaby,
  base_url: "http://localhost:4002",
  driver: Wallaby.Chrome,
  screenshot_on_failure: true,
  screenshot_dir: "tmp/e2e_screenshots",
  chrome: [headless: true, args: ["--no-sandbox", "--disable-gpu"]],
  chromedriver: [
    path:
      System.get_env("CHROMEDRIVER_PATH") ||
        System.find_executable("chromedriver") ||
        "_build/chromedriver/chromedriver"
  ]
