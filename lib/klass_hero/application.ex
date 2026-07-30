defmodule KlassHero.Application do
  @moduledoc false

  use Application

  alias KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.EnqueueInviteEmails
  alias KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.MarkInviteRegistered
  alias KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.NotifyLiveViews
  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.AdvanceVettingStepOnDocumentReview
  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.AdvanceVettingStepOnIdentityOutcome
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
    domain_event_buses() ++ projections()
  end

  defp domain_event_buses do
    [
      Supervisor.child_spec(
        {DomainEventBus, context: KlassHero.Accounts, handlers: []},
        id: :accounts_domain_event_bus
      ),
      Supervisor.child_spec(
        {DomainEventBus, context: KlassHero.Family, handlers: []},
        id: :family_domain_event_bus
      ),
      Supervisor.child_spec(
        {DomainEventBus,
         context: KlassHero.Provider,
         handlers: [
           {:verification_document_approved, {AdvanceVettingStepOnDocumentReview, :handle}},
           {:verification_document_rejected, {AdvanceVettingStepOnDocumentReview, :handle}},
           {:identity_verification_passed, {AdvanceVettingStepOnIdentityOutcome, :handle}},
           {:identity_verification_failed, {AdvanceVettingStepOnIdentityOutcome, :handle}}
         ]},
        id: :provider_domain_event_bus
      ),
      Supervisor.child_spec(
        {DomainEventBus, context: KlassHero.ProgramCatalog, handlers: []},
        id: :program_catalog_domain_event_bus
      ),
      Supervisor.child_spec(
        {DomainEventBus,
         context: KlassHero.Enrollment,
         handlers: [
           {:participant_policy_set, {NotifyLiveViews, :handle}},
           {:bulk_invites_imported, {EnqueueInviteEmails, :handle}},
           {:invite_resend_requested, {EnqueueInviteEmails, :handle}},
           {:invite_claimed, {MarkInviteRegistered, :handle}, priority: 5},
           {:invite_deleted, {NotifyLiveViews, :handle}},
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
