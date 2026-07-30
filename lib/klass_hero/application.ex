defmodule KlassHero.Application do
  @moduledoc false

  use Application

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

  # Provider is the last context still routing through the bus. The rest call their
  # reactions directly, inside the transaction that made them true.
  defp domain_event_buses do
    [
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
