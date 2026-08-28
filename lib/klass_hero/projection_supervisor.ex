defmodule KlassHero.ProjectionSupervisor do
  @moduledoc """
  Supervises all CQRS projection GenServers under an isolated subtree.

  Uses `:one_for_one` strategy — each projection crashes and restarts
  independently. No projection depends on another, so start order carries no
  meaning; cross-context data is read through the owning context's facade at
  bootstrap rather than from a sibling projection.
  """

  use Supervisor

  alias KlassHero.Provider.Projections.ProviderSessionDetails

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
    [ProviderSessionDetails]
  end

  @doc """
  Re-bootstraps every projection's read table from the authoritative write tables.

  Needed whenever write tables change without the events that maintain the read
  tables — seeding, a manual repair, a backfill migration. Order carries no
  meaning here for the same reason it carries none in the supervisor: no
  projection reads another's table.

  Every projection must be running, so this is a dev/prod call — `config/test.exs`
  sets `start_projections: false`.
  """
  @spec rebuild_all() :: :ok
  def rebuild_all do
    for projection <- projections(), do: projection.rebuild()
    :ok
  end

  @impl true
  def init(_init_arg) do
    Supervisor.init(projections(), strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
  end
end
