# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

alias ExAws.Request.Req
alias FunWithFlags.Notifications.PhoenixPubSub
alias KlassHero.Accounts.Adapters.Driven.Persistence.Repositories.UserRepository
alias KlassHero.Accounts.Adapters.Driving.Events.StaffInvitationHandler
alias KlassHero.Accounts.Scope
alias KlassHero.Enrollment.Adapters.Driven.Accounts.UserAccountResolver
alias KlassHero.Enrollment.Adapters.Driven.ACL.ChildInfoACL
alias KlassHero.Enrollment.Adapters.Driven.ACL.ParentInfoACL
alias KlassHero.Enrollment.Adapters.Driven.ACL.ParticipantDetailsACL
alias KlassHero.Enrollment.Adapters.Driven.ACL.ProgramCatalogACL
alias KlassHero.Enrollment.Adapters.Driven.ACL.ProgramScheduleACL
alias KlassHero.Enrollment.Adapters.Driven.Notifications.InviteEmailNotifier
alias KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.BulkEnrollmentInviteRepository
alias KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.EnrollmentPolicyRepository
alias KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.EnrollmentRepository
alias KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.ParticipantPolicyRepository
alias KlassHero.Enrollment.Adapters.Driving.Events.InviteFamilyReadyHandler
alias KlassHero.Family.Adapters.Driven.ACL.ChildEnrollmentACL
alias KlassHero.Family.Adapters.Driven.ACL.ChildParticipationACL
alias KlassHero.Family.Adapters.Driven.Persistence.Repositories.ChildRepository
alias KlassHero.Family.Adapters.Driven.Persistence.Repositories.ConsentRepository
alias KlassHero.Family.Adapters.Driven.Persistence.Repositories.ParentProfileRepository
alias KlassHero.Family.Adapters.Driving.Events.FamilyEventHandler
alias KlassHero.Family.Adapters.Driving.Events.InviteClaimedHandler
alias KlassHero.Messaging.Adapters.Driven.Accounts.UserResolver
alias KlassHero.Messaging.Adapters.Driven.Enrollment.EnrollmentResolver
alias KlassHero.Messaging.Adapters.Driven.ObanEmailJobScheduler
alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.AttachmentRepository
alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ConversationRepository
alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ConversationSummariesRepository
alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.EmailReplyRepository
alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.InboundEmailRepository
alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.MessageRepository
alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ParticipantRepository
alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ProgramStaffParticipantRepository
alias KlassHero.Messaging.Adapters.Driven.Provider.ProviderStaffResolver
alias KlassHero.Messaging.Adapters.Driven.ResendEmailContentAdapter
alias KlassHero.Messaging.Adapters.Driving.Events.MessagingEventHandler
alias KlassHero.Messaging.Adapters.Driving.Workers.MessageCleanupWorker
alias KlassHero.Messaging.Adapters.Driving.Workers.RetentionPolicyWorker
alias KlassHero.Participation.Adapters.Driven.ACL.ChildInfoResolver
alias KlassHero.Participation.Adapters.Driven.ACL.EnrolledChildrenResolver
alias KlassHero.Participation.Adapters.Driven.ACL.ProgramProviderResolver
alias KlassHero.Participation.Adapters.Driven.Persistence.Repositories.BehavioralNoteRepository
alias KlassHero.Participation.Adapters.Driven.Persistence.Repositories.ParticipationRepository
alias KlassHero.Participation.Adapters.Driven.Persistence.Repositories.SessionRepository
alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Repositories.ProgramListingsRepository
alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Repositories.ProgramRepository
alias KlassHero.Provider.Adapters.Driven.ACL.ParticipationSessionStatsACL
alias KlassHero.Provider.Adapters.Driven.Notifications.IncidentNotificationScheduler
alias KlassHero.Provider.Adapters.Driven.Notifications.IncidentReportedEmailNotifier
alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.IncidentReportRepository
alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.ProgramStaffAssignmentRepository
alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.ProviderProfileRepository
alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.ProviderProgramRepository
alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.SessionDetailsRepository
alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.SessionStatsRepository
alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.StaffMemberRepository
alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.VerificationDocumentRepository
alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.StaffInvitationStatusHandler
alias KlassHero.Provider.Adapters.Driving.Events.ProviderEventHandler
alias KlassHero.Shared.Adapters.Driven.Events.PubSubEventPublisher
alias KlassHero.Shared.Adapters.Driven.Events.PubSubIntegrationEventPublisher
alias KlassHero.Shared.Adapters.Driven.FeatureFlags.FunWithFlagsAdapter
alias KlassHero.Shared.Adapters.Driven.Persistence.Repositories.ProcessedEventRepository
alias KlassHero.Shared.Adapters.Driven.Storage.S3StorageAdapter
alias Swoosh.Adapters.Local

config :backpex,
  translator_function: {KlassHeroWeb.CoreComponents, :translate_backpex},
  error_translator_function: {KlassHeroWeb.CoreComponents, :translate_error}

# Use IANA timezone database (tz) so DateTime.shift_zone!/2 supports
# Europe/Berlin and other named zones with DST.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :error_tracker, repo: KlassHero.Repo, otp_app: :klass_hero, enabled: true

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
  pubsub_server: KlassHero.PubSub,
  # Configure Gettext for internationalization
  live_view: [signing_salt: "JU2osypv"]

config :klass_hero, KlassHeroWeb.Gettext,
  default_locale: "en",
  locales: ~w(en de)

# Configure Oban for background jobs
config :klass_hero, Oban,
  repo: KlassHero.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", MessageCleanupWorker},
       {"0 4 * * *", RetentionPolicyWorker}
     ]}
  ],
  # email: 1 — serialized to stay under Resend's 2 req/sec rate limit (per-node;
  #   add a rate limiter if scaling to multiple Oban nodes)
  queues: [default: 10, messaging: 5, cleanup: 2, email: 1, family: 1, critical_events: 5]

# Configure Accounts bounded context
config :klass_hero, :accounts, for_storing_users: UserRepository

# Base URL for constructing links in emails and event handlers
# (avoids boundary violations from referencing KlassHeroWeb.Endpoint in domain code)
config :klass_hero, :app_base_url, "http://localhost:4000"

# Contact information — centralized, configurable per environment
config :klass_hero, :contact,
  email: "info@mail.klasshero.com",
  phone: nil,
  address: nil

# Critical event handler registry — maps integration event topics to handlers
# that must be durably delivered via Oban. Only critical event subscriptions
# are registered here; non-critical events use PubSub-only delivery.
config :klass_hero, :critical_event_handlers, %{
  "integration:enrollment:invite_claimed" => [
    {InviteClaimedHandler, :handle_event}
  ],
  "integration:family:invite_family_ready" => [
    {InviteFamilyReadyHandler, :handle_event}
  ],
  "integration:provider:staff_member_invited" => [
    {StaffInvitationHandler, :handle_event}
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
  ]
}

# Default app timezone — used by Greeting + future per-user-tz extension.
# Configure Enrollment bounded context
config :klass_hero, :default_tz, "Europe/Berlin"

config :klass_hero, :enrollment,
  for_managing_enrollments: EnrollmentRepository,
  for_querying_enrollments: EnrollmentRepository,
  for_managing_enrollment_policies: EnrollmentPolicyRepository,
  for_querying_enrollment_policies: EnrollmentPolicyRepository,
  for_managing_participant_policies: ParticipantPolicyRepository,
  for_querying_participant_policies: ParticipantPolicyRepository,
  for_resolving_participant_details: ParticipantDetailsACL,
  for_resolving_program_schedule: ProgramScheduleACL,
  for_resolving_child_info: ChildInfoACL,
  for_resolving_parent_info: ParentInfoACL,
  for_storing_bulk_enrollment_invites: BulkEnrollmentInviteRepository,
  for_querying_bulk_enrollment_invites: BulkEnrollmentInviteRepository,
  for_resolving_program_catalog: ProgramCatalogACL,
  for_resolving_user_accounts: UserAccountResolver,
  for_sending_invite_emails: InviteEmailNotifier

# Configure Event Publisher (domain events — internal context communication)
config :klass_hero, :event_publisher,
  module: PubSubEventPublisher,
  pubsub: KlassHero.PubSub

# Configure Family bounded context
config :klass_hero, :family,
  repo: KlassHero.Repo,
  for_storing_parent_profiles: ParentProfileRepository,
  for_querying_parent_profiles: ParentProfileRepository,
  for_storing_children: ChildRepository,
  for_querying_children: ChildRepository,
  for_storing_consents: ConsentRepository,
  for_querying_consents: ConsentRepository,
  for_managing_child_enrollments: ChildEnrollmentACL,
  for_querying_child_enrollments: ChildEnrollmentACL,
  for_managing_child_participation: ChildParticipationACL

# Configure Feature Flags bounded context
config :klass_hero, :feature_flags, adapter: FunWithFlagsAdapter

# Configure Integration Event Publisher (cross-context communication)
config :klass_hero, :integration_event_publisher,
  module: PubSubIntegrationEventPublisher,
  pubsub: KlassHero.PubSub

config :klass_hero, :mailer_defaults, from: {"KlassHero", "noreply@mail.klasshero.com"}

# Configure Messaging bounded context
config :klass_hero, :messaging,
  for_managing_attachments: AttachmentRepository,
  for_querying_attachments: AttachmentRepository,
  for_managing_conversations: ConversationRepository,
  for_querying_conversations: ConversationRepository,
  for_managing_messages: MessageRepository,
  for_querying_messages: MessageRepository,
  for_managing_participants: ParticipantRepository,
  for_querying_participants: ParticipantRepository,
  for_resolving_users: UserResolver,
  for_querying_enrollments: EnrollmentResolver,
  for_resolving_program_staff: ProgramStaffParticipantRepository,
  for_resolving_provider_staff: ProviderStaffResolver,
  for_managing_conversation_summaries: ConversationSummariesRepository,
  for_querying_conversation_summaries: ConversationSummariesRepository,
  for_managing_inbound_emails: InboundEmailRepository,
  for_querying_inbound_emails: InboundEmailRepository,
  for_fetching_email_content: ResendEmailContentAdapter,
  for_managing_email_replies: EmailReplyRepository,
  for_querying_email_replies: EmailReplyRepository,
  for_scheduling_email_jobs: ObanEmailJobScheduler,
  retention: [
    days_after_program_end: 30,
    retention_period_days: 30
  ]

# Configure Participation bounded context
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

# Configure Program Catalog bounded context
config :klass_hero, :program_catalog,
  repository: ProgramRepository,
  for_listing_programs: ProgramRepository,
  for_listing_program_summaries: ProgramListingsRepository

# Configure Provider bounded context
config :klass_hero, :provider,
  repo: KlassHero.Repo,
  for_storing_provider_profiles: ProviderProfileRepository,
  for_querying_provider_profiles: ProviderProfileRepository,
  for_storing_verification_documents: VerificationDocumentRepository,
  for_querying_verification_documents: VerificationDocumentRepository,
  for_storing_staff_members: StaffMemberRepository,
  for_querying_staff_members: StaffMemberRepository,
  for_storing_program_staff_assignments: ProgramStaffAssignmentRepository,
  for_querying_program_staff_assignments: ProgramStaffAssignmentRepository,
  for_querying_session_details: SessionDetailsRepository,
  for_querying_session_stats: SessionStatsRepository,
  for_resolving_session_stats: ParticipationSessionStatsACL,
  for_storing_incident_reports: IncidentReportRepository,
  for_querying_incident_reports: IncidentReportRepository,
  for_scheduling_incident_notifications: IncidentNotificationScheduler,
  for_sending_incident_emails: IncidentReportedEmailNotifier,
  for_querying_provider_programs: ProviderProgramRepository

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
    :admin_id,
    :attendance_record_id,
    :attempted_tier,
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
    :cap,
    :category,
    :consent_id,
    :consent_type,
    :contact_id,
    :content,
    :conversation_id,
    :conversations_deleted,
    :current_count,
    :created,
    :cutoff_date,
    :document_id,
    :days_after_program_end,
    :email,
    :end_date,
    :enrollment_id,
    :error_types,
    :entity_id,
    :fields,
    :failed,
    :file_size,
    :message,
    :message_id,
    :messages_anonymized,
    :messages_deleted,
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
    :tier,
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
  sampler: {:parent_based, %{root: {:trace_id_ratio_based, 0.5}}}

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
