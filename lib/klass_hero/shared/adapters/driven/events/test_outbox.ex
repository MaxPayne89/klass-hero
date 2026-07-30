defmodule KlassHero.Shared.Adapters.Driven.Events.TestOutbox do
  @moduledoc """
  Records staged events in the process dictionary instead of enqueueing them.

  Most tests assert *what a producer emitted*, not what its consumers then
  did, and this is the only place that answer lives now. Recording
  also keeps `Oban, testing: :inline` from executing a delivery job **inside** the
  producer's transaction, which would run consumers before the write they describe
  had committed — a semantics the production path never has.

  Tests that do want end-to-end delivery swap `:outbox` to `ObanOutbox` for their
  duration and accept inline execution; see `EventTestHelper`.
  """

  @behaviour KlassHero.Shared.ForStagingEvents

  alias KlassHero.Shared.Domain.Events.Event

  @key :test_staged_events

  @doc """
  Starts recording for the current test process, discarding anything already staged.
  """
  @spec setup() :: :ok
  def setup do
    Process.put(@key, [])
    :ok
  end

  @doc """
  Every event staged by the current test process, in staging order.
  """
  @spec staged() :: [Event.t()]
  def staged, do: Process.get(@key, [])

  @impl true
  def stage(events) when is_list(events) do
    Process.put(@key, staged() ++ events)
    :ok
  end
end
