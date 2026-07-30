defmodule KlassHero.Shared.Adapters.Driven.Events.ObanOutbox do
  @moduledoc """
  Stages events as a single `EventDeliveryWorker` job.

  Oban's job table lives in the same database as the write model, so inserting
  from inside the producer's transaction is what makes the outbox transactional —
  no second store, no second commit, no window between them.

  One job per transaction rather than one per event: it preserves the in-order,
  all-or-nothing semantics the inline bus had, and costs one insert instead of N.
  The trade is that a poisoned event re-delivers its siblings on retry, which
  `processed_events` turns into wasted work rather than duplicate effects.
  """

  @behaviour KlassHero.Shared.ForStagingEvents

  alias KlassHero.Shared.Adapters.Driven.Events.CriticalEventSerializer
  alias KlassHero.Shared.Adapters.Driven.Workers.EventDeliveryWorker
  alias KlassHero.Shared.Tracing.Context

  @impl true
  def stage(events) when is_list(events) do
    args = Context.inject_into_args(%{"events" => Enum.map(events, &CriticalEventSerializer.serialize/1)})

    # insert! on purpose: a caller inside a transaction must not be able to ignore
    # a staging failure and commit the state change without its events.
    Oban.insert!(EventDeliveryWorker.new(args))

    :ok
  end
end
