import Config

alias KlassHero.Messaging.Adapters.Driven.ResendEmailContentAdapter
alias KlassHero.Participation.Adapters.Driven.ACL.ChildInfoResolver
alias KlassHero.Participation.Adapters.Driven.ACL.EnrolledChildrenResolver
alias KlassHero.Participation.Adapters.Driven.ACL.ProgramProviderResolver
alias KlassHero.Participation.Adapters.Driven.Persistence.Repositories.BehavioralNoteRepository
alias KlassHero.Participation.Adapters.Driven.Persistence.Repositories.ParticipationRepository
alias KlassHero.Participation.Adapters.Driven.Persistence.Repositories.SessionRepository
alias KlassHero.Provider.Adapters.Driven.Notifications.StubIncidentNotificationScheduler
alias KlassHero.Provider.Adapters.Driven.StripeIdentityAdapter
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

config :klass_hero, :participation,
  for_storing_sessions: SessionRepository,
  for_querying_sessions: SessionRepository,
  for_storing_participation_records: ParticipationRepository,
  for_querying_participation_records: ParticipationRepository,
  for_resolving_child_info: ChildInfoResolver,
  for_storing_behavioral_notes: BehavioralNoteRepository,
  for_querying_behavioral_notes: BehavioralNoteRepository,
  for_resolving_program_provider: ProgramProviderResolver,
  for_resolving_enrolled_children: EnrolledChildrenResolver

# Provider context overrides (test-only)
# Why: stub the incident-notification enqueue port so individual tests can
# flip it into failure mode to exercise the SubmitIncidentReport rollback path.
# In its default passthrough mode the stub forwards to the real adapter, so
# end-to-end email-pipeline tests (Oban testing: :inline) keep working.
config :klass_hero, :provider, for_scheduling_incident_notifications: StubIncidentNotificationScheduler

config :klass_hero, :resend_req_options,
  plug: {Req.Test, ResendEmailContentAdapter},
  retry: false

config :klass_hero, :storage,
  adapter: StubStorageAdapter,
  bucket: "klass-hero-test"

# Stripe Identity: a dummy secret so the adapter proceeds, and a Req.Test transport so calls are
# intercepted (no real HTTP). The adapter code path is identical to prod — only transport differs.
config :klass_hero, :stripe, secret_key: "sk_test_dummy"

config :klass_hero, :stripe_req_options,
  plug: {Req.Test, StripeIdentityAdapter},
  retry: false

config :klass_hero, :verify_webhook_signature, false
config :klass_hero, env: :test

# Outcome: disabling projections prevents sandbox leaks across async tests
config :klass_hero, sql_sandbox: true
config :klass_hero, start_projections: false

# Print only warnings and errors during test
config :logger, level: :warning

# Enable Ecto sandbox plug for Wallaby browser sessions
# Why: that query runs outside the Ecto test sandbox, poisoning the connection pool

# OpenTelemetry: disable exporting in tests; tracing tests opt in via TracingHelpers.
# Trigger: VerifiedProviders GenServer bootstraps a DB query at app startup

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
