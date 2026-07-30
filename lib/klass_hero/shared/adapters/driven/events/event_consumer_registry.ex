defmodule KlassHero.Shared.Adapters.Driven.Events.EventConsumerRegistry do
  @moduledoc """
  The one routing table from an integration event topic to everything that consumes it.

  Consumers are `{module, function}` pairs taking the event: cross-context handlers
  (`{FamilyEventHandler, :handle_event}`) and projections
  (`{ProgramListings, :project}`) are the same kind of thing here, because the
  delivery job calls them the same way.

  Replaces the pair of switches that used to decide durability — per-event
  `Event.critical?` metadata and a per-topic handler map — which had to
  *both* be on for an Oban fallback to exist, and which nothing kept in agreement.
  Being in this table is now the only condition, so a consumer either gets durable
  at-least-once delivery or is visibly absent from `config/config.exs`.

  Order within a topic is delivery order, and it is the declaration order in
  config. Consumers are independent today; the ordering is fixed only so a
  failure is reproducible.
  """

  @doc """
  Consumers for a topic, in delivery order. Empty list when the topic is unrouted.
  """
  @spec consumers_for(String.t()) :: [{module(), atom()}]
  def consumers_for(topic) when is_binary(topic) do
    :klass_hero
    |> Application.get_env(:event_consumers, %{})
    |> Map.get(topic, [])
  end

  @doc """
  Every routed topic. Used by the coverage test.
  """
  @spec topics() :: [String.t()]
  def topics do
    :klass_hero
    |> Application.get_env(:event_consumers, %{})
    |> Map.keys()
  end
end
