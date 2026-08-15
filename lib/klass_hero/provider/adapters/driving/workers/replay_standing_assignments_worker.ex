defmodule KlassHero.Provider.Adapters.Driving.Workers.ReplayStandingAssignmentsWorker do
  @moduledoc """
  One-off repair job: re-announces the standing program assignments of every
  staff member who claimed their invitation before #1312's acceptance-time
  replay existed.

  Enqueued by hand after the release that carries it, not on a schedule — the
  population it repairs is closed, and #1312 keeps it from growing:

      Oban.insert(ReplayStandingAssignmentsWorker.new(%{}))

  Runs on `:default` rather than `:messaging`: the work here is Provider staging
  events, and the Messaging-side effect happens later, on `:events`, once
  `EventDeliveryWorker` picks each one up.

  Safe to run more than once — see `Provider.replay_standing_assignments/0` for
  why every consumer absorbs a repeat.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias KlassHero.Provider

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, replayed} = Provider.replay_standing_assignments()

    Logger.info("Replayed standing staff assignments", replayed_count: replayed)

    :ok
  end
end
