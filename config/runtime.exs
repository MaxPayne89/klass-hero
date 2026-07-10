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
#     PHX_SERVER=true bin/klass_hero start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
alias KlassHero.Shared.Adapters.Driven.Storage.S3StorageAdapter
alias Swoosh.Adapters.Resend

if System.get_env("PHX_SERVER") do
  config :klass_hero, KlassHeroWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

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

  # OpenTelemetry: Only configure Honeycomb exporter if credentials are present
  # Service name is hardcoded in config.exs; the API key alone determines which Honeycomb environment receives data
  honeycomb_api_key = System.get_env("HONEYCOMB_KLASS_HERO_API_KEY")
  otel_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT")

  config :klass_hero, :app_base_url, "https://#{host}"

  if honeycomb_api_key && otel_endpoint do
    config :opentelemetry_exporter,
      otlp_protocol: :http_protobuf,
      otlp_endpoint: otel_endpoint,
      otlp_headers: [
        {"x-honeycomb-team", honeycomb_api_key}
      ]
  end

  config :klass_hero, KlassHero.Mailer,
    adapter: Resend,
    api_key: System.get_env("RESEND_API_KEY") || raise("RESEND_API_KEY not set")

  config :klass_hero, KlassHero.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6 ++ [keepalive: true],
    # Trigger: Fly.io machine resumes from suspension with stale DB connections
    # Why: protocol_violation (08P01) and idle_in_transaction timeout (25P03) indicate
    #      connections that died server-side during suspension — kill them immediately
    #      so the pool replaces them with fresh connections
    # Outcome: stale connections are pruned on first failed query instead of lingering
    disconnect_on_error_codes: [:protocol_violation, :idle_in_transaction_session_timeout]

  config :klass_hero, KlassHeroWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # ## SSL Support
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      #
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      # To get SSL working, you will need to add the `https` key
      # to your endpoint configuration:
      #
      #     config :klass_hero, KlassHeroWeb.Endpoint,
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
      # We also recommend setting `force_ssl` in your config/prod.exs,
      # ensuring no data is ever sent via http, always redirecting to https:
      #
      #     config :klass_hero, KlassHeroWeb.Endpoint,
      #       force_ssl: [hsts: true]
      #
      # Check `Plug.SSL` for all available options in `force_ssl`.

      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  config :klass_hero, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
  config :klass_hero, :resend_webhook_secret, System.get_env("RESEND_WEBHOOK_SECRET")

  # Stripe Identity (provider vetting). Read lazily and boot-tolerant: a missing key
  # never crashes boot — the client returns {:error, :stripe_not_configured} and the
  # webhook plug rejects until provisioned.
  config :klass_hero, :stripe, secret_key: System.get_env("STRIPE_SECRET_KEY")
  config :klass_hero, :stripe_webhook_secret, System.get_env("STRIPE_WEBHOOK_SECRET")

  # Trigger: dev Fly.io instance needs to receive test webhook payloads via curl
  # Why: Svix signature verification requires a live webhook secret and real headers
  # Outcome: set VERIFY_WEBHOOK_SIGNATURE=false on dev instance to skip verification
  if System.get_env("VERIFY_WEBHOOK_SIGNATURE") == "false" do
    config :klass_hero, :verify_webhook_signature, false
  end

  # Storage configuration for production
  # Trigger: Tigris storage on Fly.io auto-sets AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
  # Why: single bucket with per-object ACLs — Fly.io Tigris allows one bucket per app
  # Outcome: public files get acl: :public_read, private files use signed URLs
  config :klass_hero, :storage,
    adapter: S3StorageAdapter,
    bucket: System.get_env("STORAGE_BUCKET") || raise("STORAGE_BUCKET not set"),
    access_key_id: System.get_env("AWS_ACCESS_KEY_ID") || raise("AWS_ACCESS_KEY_ID not set"),
    secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY") || raise("AWS_SECRET_ACCESS_KEY not set")
end
