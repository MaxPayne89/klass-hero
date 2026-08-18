defmodule KlassHero.Shared.EventReplay do
  @moduledoc """
  Re-delivers an integration event that permanently failed delivery.

  Shared's public surface is its root modules; everything under `adapters/` is
  internal to it. This module exists so a caller outside Shared — today the admin's
  `ReplayEventAction` — has a root-level entry point to reach for, rather than
  naming `Adapters.Driven.Workers.EventDeliveryWorker` and making a deep path the
  next caller copies.

  It forwards and does nothing else, deliberately. The registry check, the
  transaction and the job-args shape stay in `EventDeliveryWorker`, next to the
  `compensate/2` that writes the row this replays: that shape is the worker's, and
  a second module building it would give it a second owner.

  See `EventDeliveryWorker.replay/1` for what replay guarantees — chiefly that
  consumers already recorded in `processed_events` do not run again, and that a row
  naming a consumer no longer in `:event_consumers` is refused rather than
  delivered to nobody.
  """

  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.UndeliveredEvent
  alias KlassHero.Shared.Adapters.Driven.Workers.EventDeliveryWorker

  @doc """
  Re-enqueues delivery of a dead-lettered event to the consumers that missed it.
  """
  @spec replay(UndeliveredEvent.t()) :: :ok | {:error, {:retired_consumers, [String.t()]}}
  defdelegate replay(undelivered_event), to: EventDeliveryWorker
end
