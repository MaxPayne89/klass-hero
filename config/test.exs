import Config

alias KlassHero.Messaging.Adapters.Driven.ResendEmailContentAdapter
alias KlassHero.Provider.StripeIdentity
alias KlassHero.Shared.Adapters.Driven.Events.TestEventPublisher
alias KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher
alias KlassHero.Shared.Adapters.Driven.FeatureFlags.StubFeatureFlagsAdapter
alias KlassHero.Shared.Adapters.Driven.Storage.StubStorageAdapter
alias Swoosh.Adapters.Test

# The one source of truth for the test HTTP port, shared by the endpoint and Wallaby's
# base_url below. Override with TEST_PORT when 4002 is taken (another worktree, or an
# unrelated project on the same machine).
test_port = String.to_integer(System.get_env("TEST_PORT") || "4002")

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

# Bind a real socket ONLY for the Wallaby e2e suite (`mix test.e2e`, which sets
# WALLABY_E2E). Everything else drives the endpoint through Plug/LiveView test helpers and
# needs no listener — binding unconditionally made one global port a prerequisite for the
# entire suite, so any other worktree or project holding it blocked every test run.
config :klass_hero, KlassHeroWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: test_port],
  secret_key_base: "gY/oKuAYeC5ExhHrtu1JBwrpQdoGwtPOo3X9GdS7CFOnLe0eqRQ9w4cyV1MqvoYc",
  server: System.get_env("WALLABY_E2E") == "true"

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

# Stripe Identity: a dummy key keeps the client past its configured? guard, and the
# Req.Test plug routes create_session/1 to per-test stubs (same code path as prod).
config :klass_hero, :stripe, secret_key: "sk_test_dummy"

config :klass_hero, :stripe_req_options,
  plug: {Req.Test, StripeIdentity},
  retry: false

config :klass_hero, :stripe_webhook_secret, "whsec_test_secret"
config :klass_hero, :verify_webhook_signature, false
config :klass_hero, env: :test

# Enable Ecto sandbox plug for Wallaby browser sessions
config :klass_hero, sql_sandbox: true

# Trigger: VerifiedProviders GenServer bootstraps a DB query at app startup
# Why: that query runs outside the Ecto test sandbox, poisoning the connection pool
# Outcome: disabling projections prevents sandbox leaks across async tests
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
  base_url: "http://localhost:#{test_port}",
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
