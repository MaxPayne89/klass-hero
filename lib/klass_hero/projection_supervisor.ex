defmodule KlassHero.ProjectionSupervisor do
  @moduledoc """
  Supervises all CQRS projection GenServers under an isolated subtree.

  Uses `:one_for_one` strategy — each projection crashes and restarts
  independently. No projection depends on another, so start order carries no
  meaning; cross-context data is read through the owning context's facade at
  bootstrap rather than from a sibling projection.
  """

  use Supervisor

  alias KlassHero.Messaging.Adapters.Driven.Projections.ConversationSummaries
  alias KlassHero.Messaging.Adapters.Driven.Projections.EnrolledChildren
  alias KlassHero.ProgramCatalog.Adapters.Driven.Projections.ProgramListings
  alias KlassHero.Provider.Adapters.Driven.Projections.ProviderPrograms
  alias KlassHero.Provider.Adapters.Driven.Projections.ProviderSessionDetails
  alias KlassHero.Provider.Adapters.Driven.Projections.ProviderSessionStats

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Every projection module. Public so the consumer-registry coverage test can check
  each one's `topics/0` is routed — a projection missing from the registry receives
  nothing and looks exactly like a read table that is merely behind.
  """
  @spec projections() :: [module()]
  def projections do
    [
      ProgramListings,
      EnrolledChildren,
      ConversationSummaries,
      ProviderSessionStats,
      ProviderPrograms,
      ProviderSessionDetails
    ]
  end

  @impl true
  def init(_init_arg) do
    Supervisor.init(projections(), strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
  end
end
