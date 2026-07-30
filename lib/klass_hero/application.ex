defmodule KlassHero.Application do
  @moduledoc false

  use Application

  alias KlassHero.Accounts.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents
  alias KlassHero.Accounts.Adapters.Driving.Events.StaffInvitationHandler
  alias KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.EnqueueInviteEmails
  alias KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.MarkInviteRegistered
  alias KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.NotifyLiveViews
  alias KlassHero.Enrollment.Adapters.Driving.Events.InviteFamilyReadyHandler
  alias KlassHero.Family.Adapters.Driving.Events.FamilyEventHandler
  alias KlassHero.Family.Adapters.Driving.Events.InviteClaimedHandler
  alias KlassHero.Messaging.Adapters.Driving.Events.MessagingEventHandler
  alias KlassHero.Messaging.Adapters.Driving.Events.StaffAssignmentHandler
  alias KlassHero.Participation.Adapters.Driving.Events.EventHandlers.SeedSessionRosterHandler
  alias KlassHero.Participation.Adapters.Driving.Events.ParticipationEventHandler
  alias KlassHero.ProgramCatalog.Adapters.Driving.Events.EnrollmentEventHandler
  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.AdvanceVettingStepOnDocumentReview
  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.AdvanceVettingStepOnIdentityOutcome
  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.StaffInvitationStatusHandler
  alias KlassHero.Provider.Adapters.Driving.Events.ProviderEventHandler
  alias KlassHero.Shared.Adapters.Driven.Events.EventSubscriber
  alias KlassHero.Shared.DomainEventBus

  @impl true
  def start(_type, _args) do
    children = infrastructure_children() ++ domain_children() ++ [KlassHeroWeb.Endpoint]

    opts = [strategy: :one_for_one, name: KlassHero.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    KlassHeroWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp infrastructure_children do
    [
      KlassHeroWeb.Telemetry,
      KlassHero.Repo,
      {DNSCluster, query: Application.get_env(:klass_hero, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: KlassHero.PubSub},
      {Oban, Application.fetch_env!(:klass_hero, Oban)},
      {Task.Supervisor, name: KlassHero.TaskSupervisor}
    ]
  end

  defp domain_children do
    domain_event_buses() ++
      integration_event_subscribers() ++
      projections()
  end

  defp domain_event_buses do
    [
      Supervisor.child_spec(
        {DomainEventBus,
         context: KlassHero.Accounts,
         handlers: [
           {:user_registered, {PromoteIntegrationEvents, :handle}, priority: 10},
           {:user_confirmed, {PromoteIntegrationEvents, :handle}, priority: 10},
           {:user_anonymized, {PromoteIntegrationEvents, :handle}, priority: 10}
         ]},
        id: :accounts_domain_event_bus
      ),
      Supervisor.child_spec(
        {DomainEventBus,
         context: KlassHero.Family,
         handlers: [
           {:child_data_anonymized,
            {KlassHero.Family.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents, :handle}, priority: 10},
           {:invite_family_ready,
            {KlassHero.Family.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents, :handle}, priority: 10},
           {:child_created, {KlassHero.Family.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents, :handle},
            priority: 10},
           {:child_updated, {KlassHero.Family.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents, :handle},
            priority: 10}
         ]},
        id: :family_domain_event_bus
      ),
      Supervisor.child_spec(
        {DomainEventBus,
         context: KlassHero.Provider,
         handlers: [
           {:verification_document_approved, {AdvanceVettingStepOnDocumentReview, :handle}},
           {:verification_document_rejected, {AdvanceVettingStepOnDocumentReview, :handle}},
           {:identity_verification_passed, {AdvanceVettingStepOnIdentityOutcome, :handle}},
           {:identity_verification_failed, {AdvanceVettingStepOnIdentityOutcome, :handle}},
           {:staff_assigned_to_program,
            {KlassHero.Provider.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents, :handle}},
           {:staff_unassigned_from_program,
            {KlassHero.Provider.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents, :handle}}
         ]},
        id: :provider_domain_event_bus
      ),
      Supervisor.child_spec(
        {DomainEventBus,
         context: KlassHero.ProgramCatalog,
         handlers: [
           {:program_created,
            {KlassHero.ProgramCatalog.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents, :handle},
            priority: 10},
           {:program_updated,
            {KlassHero.ProgramCatalog.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents, :handle},
            priority: 10}
         ]},
        id: :program_catalog_domain_event_bus
      ),
      Supervisor.child_spec(
        {DomainEventBus,
         context: KlassHero.Enrollment,
         handlers: [
           {:participant_policy_set, {NotifyLiveViews, :handle}},
           {:participant_policy_set,
            {KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents, :handle},
            priority: 10},
           {:bulk_invites_imported, {EnqueueInviteEmails, :handle}},
           {:invite_resend_requested, {EnqueueInviteEmails, :handle}},
           {:invite_claimed, {MarkInviteRegistered, :handle}, priority: 5},
           {:invite_claimed,
            {KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents, :handle},
            priority: 10},
           {:invite_deleted, {NotifyLiveViews, :handle}},
           {:enrollment_cancelled,
            {KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents, :handle},
            priority: 10},
           {:enrollment_created,
            {KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents, :handle},
            priority: 10},
           {:enrollment_confirmed, {NotifyLiveViews, :handle}}
         ]},
        id: :enrollment_domain_event_bus
      ),
      Supervisor.child_spec(
        {DomainEventBus,
         context: KlassHero.Messaging,
         handlers: [
           {:conversation_created,
            {KlassHero.Messaging.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}},
           {:message_sent, {KlassHero.Messaging.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}},
           {:messages_read, {KlassHero.Messaging.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}},
           {:conversations_archived,
            {KlassHero.Messaging.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}},
           {:retention_enforced, {KlassHero.Messaging.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}}
         ]},
        id: :messaging_domain_event_bus
      ),
      Supervisor.child_spec(
        {DomainEventBus,
         context: KlassHero.Participation,
         handlers: [
           {:session_created, {KlassHero.Participation.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}},
           {:sessions_generated,
            {KlassHero.Participation.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}},
           {:session_cancelled,
            {KlassHero.Participation.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}},
           {:session_started, {KlassHero.Participation.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}},
           {:session_completed,
            {KlassHero.Participation.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}},
           {:child_checked_in,
            {KlassHero.Participation.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}},
           {:child_checked_out,
            {KlassHero.Participation.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}},
           {:child_marked_absent,
            {KlassHero.Participation.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}},
           {:session_note_submitted,
            {KlassHero.Participation.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}},
           {:session_note_approved,
            {KlassHero.Participation.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}},
           {:session_note_rejected,
            {KlassHero.Participation.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}},
           {:roster_seeded, {KlassHero.Participation.Adapters.Driving.Events.EventHandlers.NotifyLiveViews, :handle}}
         ]},
        id: :participation_domain_event_bus
      )
    ]
  end

  @doc """
  Integration-event subscriber child specs.

  Public so a test can check each subscriber's `topics:` covers everything its
  handler declares in `subscribed_events/0` — `EventSubscriber` subscribes off
  the literal topic list and never consults the handler, so the two drift
  silently, and a handler clause that never receives its event looks exactly
  like a feature that quietly does nothing.
  """
  def integration_event_subscribers do
    [
      Supervisor.child_spec(
        {EventSubscriber,
         handler: FamilyEventHandler,
         topics: [
           "integration:accounts:user_registered",
           "integration:accounts:user_confirmed",
           "integration:accounts:user_anonymized"
         ],
         message_tag: :integration_event,
         event_label: "Integration event"},
        id: :family_integration_event_subscriber
      ),
      Supervisor.child_spec(
        {EventSubscriber,
         handler: ProviderEventHandler,
         topics: [
           "integration:accounts:user_registered",
           "integration:accounts:user_confirmed",
           "integration:accounts:user_anonymized"
         ],
         message_tag: :integration_event,
         event_label: "Integration event"},
        id: :provider_integration_event_subscriber
      ),
      Supervisor.child_spec(
        {EventSubscriber,
         handler: MessagingEventHandler,
         topics: ["integration:accounts:user_anonymized"],
         message_tag: :integration_event,
         event_label: "Integration event"},
        id: :messaging_integration_event_subscriber
      ),
      Supervisor.child_spec(
        {EventSubscriber,
         handler: ParticipationEventHandler,
         topics: [
           "integration:family:child_data_anonymized",
           "integration:program_catalog:program_created",
           "integration:program_catalog:program_updated",
           "integration:enrollment:enrollment_created"
         ],
         message_tag: :integration_event,
         event_label: "Integration event"},
        id: :participation_integration_event_subscriber
      ),
      Supervisor.child_spec(
        {EventSubscriber,
         handler: EnrollmentEventHandler,
         topics: ["integration:enrollment:participant_policy_set"],
         message_tag: :integration_event,
         event_label: "Integration event"},
        id: :program_catalog_enrollment_integration_event_subscriber
      ),
      # Family listens for invite_claimed from Enrollment
      Supervisor.child_spec(
        {EventSubscriber,
         handler: InviteClaimedHandler,
         topics: ["integration:enrollment:invite_claimed"],
         message_tag: :integration_event,
         event_label: "Integration event"},
        id: :family_enrollment_invite_subscriber
      ),
      # Enrollment listens for invite_family_ready from Family
      Supervisor.child_spec(
        {EventSubscriber,
         handler: InviteFamilyReadyHandler,
         topics: ["integration:family:invite_family_ready"],
         message_tag: :integration_event,
         event_label: "Integration event"},
        id: :enrollment_family_invite_subscriber
      ),
      # Participation seeds session rosters, whether a session was created by hand
      # or derived from a program's schedule.
      Supervisor.child_spec(
        {EventSubscriber,
         handler: SeedSessionRosterHandler,
         topics: [
           "integration:participation:session_created",
           "integration:participation:sessions_generated"
         ],
         message_tag: :integration_event,
         event_label: "Integration event"},
        id: :participation_seed_roster_subscriber
      ),
      # Accounts listens for staff_member_invited from Provider
      Supervisor.child_spec(
        {EventSubscriber,
         handler: StaffInvitationHandler,
         topics: ["integration:provider:staff_member_invited"],
         message_tag: :integration_event,
         event_label: "Integration event"},
        id: :staff_invitation_event_subscriber
      ),
      # Provider listens for staff invitation status events from Accounts
      Supervisor.child_spec(
        {EventSubscriber,
         handler: StaffInvitationStatusHandler,
         topics: [
           "integration:accounts:staff_invitation_sent",
           "integration:accounts:staff_invitation_failed",
           "integration:accounts:staff_user_registered"
         ],
         message_tag: :integration_event,
         event_label: "Integration event"},
        id: :staff_invitation_status_subscriber
      ),
      # Messaging listens for staff assignment events from Provider
      Supervisor.child_spec(
        {EventSubscriber,
         handler: StaffAssignmentHandler,
         topics: [
           "integration:provider:staff_assigned_to_program",
           "integration:provider:staff_unassigned_from_program"
         ],
         message_tag: :integration_event,
         event_label: "Integration event"},
        id: :messaging_staff_assignment_subscriber
      )
    ]
  end

  # Trigger: start_projections is false in test config
  # Why: projections bootstrap DB queries outside the Ecto sandbox, poisoning the
  #      connection pool and causing sandbox leaks across async tests
  # Outcome: projections skipped in test env, started normally elsewhere
  defp projections do
    if Application.get_env(:klass_hero, :start_projections, true) do
      [{KlassHero.ProjectionSupervisor, []}]
    else
      []
    end
  end
end
