# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

alias ExAws.Request.Req
alias FunWithFlags.Notifications.PhoenixPubSub
alias KlassHero.Accounts.Scope
alias KlassHero.Accounts.StaffInvitationHandler
alias KlassHero.Enrollment.Adapters.Driving.Events.InviteFamilyReadyHandler
alias KlassHero.Enrollment.Adapters.Driving.Workers.SendInviteEmailWorker
alias KlassHero.Family.Adapters.Driving.Events.FamilyEventHandler
alias KlassHero.Family.Adapters.Driving.Events.InviteClaimedHandler
alias KlassHero.Family.Adapters.Driving.Workers.ProcessInviteClaimWorker
alias KlassHero.Messaging.Adapters.Driven.Projections.ConversationSummaries
alias KlassHero.Messaging.Adapters.Driven.Projections.EnrolledChildren
alias KlassHero.Messaging.Adapters.Driving.Events.MessagingEventHandler
alias KlassHero.Messaging.Adapters.Driving.Events.StaffAssignmentHandler
alias KlassHero.Messaging.Adapters.Driving.Workers.FetchEmailContentWorker
alias KlassHero.Messaging.Adapters.Driving.Workers.MessageCleanupWorker
alias KlassHero.Messaging.Adapters.Driving.Workers.RetentionPolicyWorker
alias KlassHero.Messaging.Adapters.Driving.Workers.SendEmailReplyWorker
alias KlassHero.Participation.Adapters.Driving.Events.EventHandlers.SeedSessionRosterHandler
alias KlassHero.Participation.Adapters.Driving.Events.ParticipationEventHandler
alias KlassHero.ProgramCatalog.Adapters.Driven.Projections.ProgramListings
alias KlassHero.ProgramCatalog.Adapters.Driving.Events.EnrollmentEventHandler
alias KlassHero.Provider.Adapters.Driven.Projections.ProviderPrograms
alias KlassHero.Provider.Adapters.Driven.Projections.ProviderSessionDetails
alias KlassHero.Provider.Adapters.Driven.Projections.ProviderSessionStats
alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.StaffInvitationStatusHandler
alias KlassHero.Provider.Adapters.Driving.Events.ProviderEventHandler
alias KlassHero.Shared.Adapters.Driven.Events.ObanOutbox
alias KlassHero.Shared.Adapters.Driven.FeatureFlags.FunWithFlagsAdapter
alias KlassHero.Shared.Adapters.Driven.Persistence.Repositories.ProcessedEventRepository
alias KlassHero.Shared.Adapters.Driven.Storage.S3StorageAdapter
alias KlassHero.Shared.Adapters.Driven.Workers.CompensationSweepWorker
alias KlassHero.Shared.Adapters.Driven.Workers.EventDeliveryWorker
alias KlassHero.Shared.ErrorContextFilter
alias KlassHero.Shared.ErrorStoreRepo
alias Swoosh.Adapters.Local

# The supported-locale set, declared once. Config owns it because config.exs is
# evaluated before the app compiles and so can never read a module — a domain
# module holding the literal could not feed the Gettext key below. Two `config`
# calls consume these bindings (Quokka sorts them elsewhere in this file); they
# cannot drift because there is only one binding.
#
# Adding a locale means this line, `priv/gettext/<locale>/`, and a `label/1` +
# `flag/1` clause in `KlassHeroWeb.Locale`. All four are asserted together by
# "every supported locale is fully wired" in `locale_test.exs`.
supported_locales = ~w(en de)
default_locale = "en"

config :backpex,
  translator_function: {KlassHeroWeb.CoreComponents, :translate_backpex},
  error_translator_function: {KlassHeroWeb.CoreComponents, :translate_error}

# Use IANA timezone database (tz) so DateTime.shift_zone!/2 supports
# Europe/Berlin and other named zones with DST.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# `filter` narrows what gets persisted: Oban job args reach here in full, and some
# carry child health data. See KlassHero.Shared.ErrorContextFilter.
#
# `repo` is deliberately NOT KlassHero.Repo. ErrorTracker's filter reaches the context only,
# so the exception message lands in `reason` unfiltered; the shim narrows it at the write
# boundary, which is the one point every report path passes through (#1398).
config :error_tracker,
  repo: ErrorStoreRepo,
  otp_app: :klass_hero,
  enabled: true,
  filter: ErrorContextFilter

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  klass_hero: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Use Req (via Finch/Mint) instead of hackney for ExAws HTTP requests
config :ex_aws, http_client: Req

# Configure feature flags infrastructure (fun_with_flags)
config :fun_with_flags, :cache_bust_notifications,
  enabled: true,
  adapter: PhoenixPubSub,
  client: KlassHero.PubSub

config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: KlassHero.Repo

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
# Configures the endpoint
config :klass_hero, KlassHero.Mailer, adapter: Local

config :klass_hero, KlassHeroWeb.Endpoint,
  url: [host: "localhost", port: 4000],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: KlassHeroWeb.ErrorHTML, json: KlassHeroWeb.ErrorJSON],
    layout: false
  ],

  # `:locales` is not a Gettext option — the backend derives its own set from the
  # .po files on disk. It lives under this key because `mix lint_translations`
  # reads it here to decide which locales require translations.
  pubsub_server: KlassHero.PubSub,
  live_view: [signing_salt: "JU2osypv"]

config :klass_hero, KlassHeroWeb.Gettext,
  default_locale: default_locale,
  locales: supported_locales

# Configure Oban for background jobs
config :klass_hero, Oban,
  repo: KlassHero.Repo,
  plugins: [
    # max_age is in seconds and defaults to 60, which deletes a permanently-failed job before anyone
    # can open /oban to see what happened.
    {Oban.Plugins.Pruner, max_age: 604_800},
    # Rescues jobs left `executing` by a machine that went away — routine under
    # auto_stop_machines = "suspend". Rescuing is time-based with no liveness check, so the 60-minute
    # default is really a duplicate-execution budget: no job here runs anywhere near that long. Do not
    # lower it without bounding worker runtime via `timeout/1`.
    Oban.Plugins.Lifeline,
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", MessageCleanupWorker},
       {"0 4 * * *", RetentionPolicyWorker},
       # Every 5 minutes, not daily: this is what makes a permanently-failed invite or
       # email visible to the provider when the job died without running its own gate.
       # A day's delay would leave the row looking pending for a day.
       {"*/5 * * * *", CompensationSweepWorker}
     ]}
  ],
  # email: 1 — serialized to stay under Resend's 2 req/sec rate limit (per-node;
  #   add a rate limiter if scaling to multiple Oban nodes)
  # events: 5 — every event goes here; since ADR-0014 there is no other kind.
  queues: [default: 10, messaging: 5, cleanup: 2, email: 1, family: 1, events: 5]

# Base URL for constructing links in emails and event handlers
# (avoids boundary violations from referencing KlassHeroWeb.Endpoint in domain code)
config :klass_hero, :app_base_url, "http://localhost:4000"

# Workers whose permanently-dead jobs the compensation sweep reconciles. A worker
# implementing `compensate/2` but missing here is never swept — the gate inside its
# attempt still runs, but the three routes that bypass it (Lifeline discarding an orphan,
# a raise, an early `{:discard, _}`) go uncompensated. The sweep also filters on this list
# in SQL, so an unlisted worker's discarded jobs are not re-examined every tick.
config :klass_hero, :compensating_workers, [
  ProcessInviteClaimWorker,
  SendInviteEmailWorker,
  FetchEmailContentWorker,
  SendEmailReplyWorker,
  # The odd one out: its compensating fact is a negative one — a dead-letter record
  # saying these consumers never reacted and now never will. It compensates only
  # here, never inside its own attempt, because the routes an in-attempt gate cannot
  # see are exactly the ones that lose an event silently.
  EventDeliveryWorker
]

# Contact information — centralized, configurable per environment
config :klass_hero, :contact,
  email: "info@mail.klasshero.com",
  phone: nil,
  address: nil

# Default app timezone — used by Greeting + future per-user-tz extension.
# Configure Enrollment bounded context
config :klass_hero, :default_tz, "Europe/Berlin"

# Every consumer of every integration event topic, in delivery order. Read by the
# outbox delivery job; see EventConsumerRegistry for why handlers and projections
# are the same kind of entry.
#
# Being in this table is also what decides whether an event is staged at all:
# `Shared.Outbox` drops one no consumer is registered for, since the delivery
# job would have nothing to do with it.
config :klass_hero, :event_consumers, %{
  # Accounts
  "integration:accounts:user_registered" => [
    {FamilyEventHandler, :handle_event},
    {ProviderEventHandler, :handle_event}
  ],
  "integration:accounts:user_confirmed" => [
    {FamilyEventHandler, :handle_event},
    {ProviderEventHandler, :handle_event}
  ],
  "integration:accounts:user_anonymized" => [
    {FamilyEventHandler, :handle_event},
    {ProviderEventHandler, :handle_event},
    {MessagingEventHandler, :handle_event}
  ],
  "integration:accounts:staff_invitation_sent" => [
    {StaffInvitationStatusHandler, :handle_event}
  ],
  "integration:accounts:staff_invitation_failed" => [
    {StaffInvitationStatusHandler, :handle_event}
  ],
  "integration:accounts:staff_user_registered" => [
    {StaffInvitationStatusHandler, :handle_event}
  ],

  # Family
  "integration:family:child_data_anonymized" => [
    {ParticipationEventHandler, :handle_event}
  ],
  "integration:family:invite_family_ready" => [
    {InviteFamilyReadyHandler, :handle_event}
  ],
  "integration:family:child_created" => [
    {EnrolledChildren, :project}
  ],
  "integration:family:child_updated" => [
    {EnrolledChildren, :project}
  ],

  # Program Catalog
  "integration:program_catalog:program_created" => [
    {ParticipationEventHandler, :handle_event},
    {ProgramListings, :project},
    {ProviderPrograms, :project}
  ],
  "integration:program_catalog:program_updated" => [
    {ParticipationEventHandler, :handle_event},
    {ProgramListings, :project},
    {ProviderPrograms, :project}
  ],

  # Enrollment
  "integration:enrollment:enrollment_created" => [
    {ParticipationEventHandler, :handle_event},
    {EnrolledChildren, :project}
  ],
  "integration:enrollment:enrollment_cancelled" => [
    {EnrolledChildren, :project}
  ],
  "integration:enrollment:participant_policy_set" => [
    {EnrollmentEventHandler, :handle_event}
  ],
  "integration:enrollment:invite_claimed" => [
    {InviteClaimedHandler, :handle_event}
  ],

  # Provider
  "integration:provider:staff_member_invited" => [
    {StaffInvitationHandler, :handle_event}
  ],
  "integration:provider:staff_assigned_to_program" => [
    {StaffAssignmentHandler, :handle_event},
    {ProviderSessionDetails, :project}
  ],
  "integration:provider:staff_unassigned_from_program" => [
    {StaffAssignmentHandler, :handle_event},
    {ProviderSessionDetails, :project}
  ],
  # Session-grain overrides, routed to StaffAssignmentHandler since #784.
  # Conversation membership is still program-scoped — what changed is that
  # entitlement to it is the *union* of the two grains, because a session override
  # admits someone holding no program assignment at all. So a substitute joins the
  # program's conversations, and leaves them only once no claim of either grain
  # remains. This registry is also `Outbox.stage/2`'s filter, so these two lines
  # are the wiring, not a preference.
  "integration:provider:staff_assigned_to_session" => [
    {ProviderSessionDetails, :project},
    {StaffAssignmentHandler, :handle_event}
  ],
  "integration:provider:staff_unassigned_from_session" => [
    {ProviderSessionDetails, :project},
    {StaffAssignmentHandler, :handle_event}
  ],
  # Deliberately NOT routed to StaffAssignmentHandler: deactivation ends the
  # employment link but leaves assignments standing, so conversation membership
  # survives — reactivating cannot give it back (#1237).
  "integration:provider:staff_member_deactivated" => [
    {ProviderSessionDetails, :project}
  ],
  # `integration:provider:provider_verified` / `provider_unverified` have no consumers
  # since #1195: program cards read trust state from Provider's facade per render rather
  # than from a denormalised column. The events are still produced (the `verified` fact
  # and its audit trail are load-bearing); `Outbox.stage/2` drops them for want of a
  # consumer. Register one here to revive delivery.

  # Participation
  "integration:participation:session_created" => [
    {SeedSessionRosterHandler, :handle_event},
    {ProviderSessionDetails, :project}
  ],
  "integration:participation:sessions_generated" => [
    {SeedSessionRosterHandler, :handle_event},
    {ProviderSessionDetails, :project}
  ],
  "integration:participation:session_started" => [
    {ProviderSessionDetails, :project}
  ],
  "integration:participation:session_completed" => [
    {ProviderSessionDetails, :project},
    {ProviderSessionStats, :project}
  ],
  "integration:participation:session_cancelled" => [
    {ProviderSessionDetails, :project}
  ],
  "integration:participation:roster_seeded" => [
    {ProviderSessionDetails, :project}
  ],
  "integration:participation:child_checked_in" => [
    {ProviderSessionDetails, :project}
  ],
  "integration:participation:child_checked_out" => [
    {ProviderSessionDetails, :project}
  ],
  "integration:participation:child_marked_absent" => [
    {ProviderSessionDetails, :project}
  ],

  # Messaging
  "integration:messaging:conversation_created" => [
    {ConversationSummaries, :project},
    {EnrolledChildren, :project}
  ],
  "integration:messaging:message_sent" => [
    {ConversationSummaries, :project}
  ],
  "integration:messaging:messages_read" => [
    {ConversationSummaries, :project}
  ],
  "integration:messaging:conversations_archived" => [
    {ConversationSummaries, :project}
  ],
  "integration:messaging:message_data_anonymized" => [
    {ConversationSummaries, :project}
  ],
  "integration:messaging:participant_added" => [
    {ConversationSummaries, :project}
  ],
  "integration:messaging:participant_removed" => [
    {ConversationSummaries, :project}
  ]
}

# Configure Feature Flags bounded context
config :klass_hero, :feature_flags, adapter: FunWithFlagsAdapter

# Read by `KlassHero.Shared.Locales`, which is what application code calls.
config :klass_hero, :locales,
  supported: supported_locales,
  default: default_locale

config :klass_hero, :mailer_defaults, from: {"KlassHero", "noreply@mail.klasshero.com"}

config :klass_hero, :messaging,
  retention: [
    days_after_program_end: 30,
    # Family context needs no port wiring: it is conventional Phoenix (context module
    # + Ecto schemas calling Repo directly). Its outbound cross-context ACLs are
    # called by KlassHero.Family directly, not via dependency injection.
    retention_period_days: 30
  ]

# Durable delivery for staged events. See Shared.Outbox.
config :klass_hero, :outbox, module: ObanOutbox

# How long after a program's end_date its staff keep access to its sessions and
# rosters (#1082). Its own key, not `:messaging, :retention` below: that window
# governs when a conversation is archived for data retention, this one governs
# when a person stops being allowed to see a child's record. Same shape today,
# different reasons to change.
config :klass_hero, :program_access, closed_after_days: 14
config :klass_hero, :resend_req_options, []

config :klass_hero, :scopes,
  user: [
    default: true,
    module: Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: KlassHero.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

# Configure Shared bounded context (critical event infrastructure)
config :klass_hero, :shared, for_tracking_processed_events: ProcessedEventRepository

# Configure Storage (defaults, overridden per environment)
config :klass_hero, :storage,
  adapter: S3StorageAdapter,
  bucket: "klass-hero-dev"

# Participation context needs no port wiring (conventional Phoenix; ACL adapters called directly).
config :klass_hero,
  ecto_repos: [KlassHero.Repo],
  generators: [timestamp_type: :utc_datetime]

config :klass_hero, env: Mix.env()

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :session_id,
    :reason,
    :provider_id,
    :record_id,
    :child_id,
    :program_id,
    :provider_name,
    :added_count,
    :replayed_count,
    :retired_consumers,
    :admin_id,
    :attendance_record_id,
    :bucket,
    :child_name,
    :limit,
    :has_cursor,
    :returned_count,
    :has_more,
    :errors,
    :error_id,
    :identity_id,
    :instructor_id,
    :instructor_name,
    :key,
    :business_name,
    :first_name,
    :last_name,
    :parent_id,
    :parent_user_id,
    :count,
    :current_user_id,
    :live_view,
    :search_query,
    :sort,
    :result_count,
    :duration_ms,
    :target_ms,
    :page_has_more,
    :event_id,
    :event_type,
    :aggregate_id,
    :topic,
    :error,
    :title,
    :lock_version,
    :cursor,
    :archived_count,
    :category,
    :consent_id,
    :consent_type,
    :contact_id,
    :content,
    :conversation_id,
    :conversations_deleted,
    :created,
    :cutoff_date,
    :document_id,
    :days_after_program_end,
    :email,
    :end_date,
    :enrollment_id,
    :error_types,
    :entity,
    :entity_id,
    :fields,
    :id,
    :failed,
    :file_size,
    :message,
    :message_id,
    :messages_anonymized,
    :messages_deleted,
    :incident_reports_anonymized,
    :staff_members_anonymized,
    :name,
    :opts,
    :participant_id,
    :path,
    :participants_updated,
    :recipient_count,
    :remaining,
    :retention_period_days,
    :start_date,
    :subject,
    :submitted_at,
    :timestamp,
    :type,
    :used,
    :user_count,
    :user_id,
    :conversation_count,
    :initiator_id,
    :message_count,
    :read_at,
    :retention_days,
    :sender_id,
    :note_id,
    :stacktrace,
    :handler,
    :handler_ref,
    :attempt,
    :max_attempts,
    :doc_type,
    :kind,
    :result,
    :retry_count,
    :upload,
    :row_index,
    :batch_size,
    :conversation_type,
    :invite_id,
    :program_count,
    :status,
    :step,
    :user_type,
    :broadcast_id,
    :direct_conversation_id,
    :staff_member_id,
    :staff_user_id,
    :file_url,
    :photo_url,
    :storage_path,
    :filename,
    :received,
    :incident_report_id,
    :provider_profile_id
  ]

config :opentelemetry, :resource,
  service: [
    name: "klass-hero",
    namespace: "klass-hero"
  ]

# OpenTelemetry base configuration
config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp,
  # Keep every root trace (1.0). At current volume, 50% sampling discarded half the
  # data for no benefit — the Honeycomb free tier allows 20M events/month and we are
  # orders of magnitude under it. Reintroduce a ratio (e.g. 0.25) only once trace
  # volume approaches that budget.
  sampler: {:parent_based, %{root: {:trace_id_ratio_based, 1.0}}}

# GDPR: Filter sensitive parameters from logs
config :phoenix, :filter_parameters, [
  "password",
  "password_confirmation",
  "email",
  "name"
]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  klass_hero: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
