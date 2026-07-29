defmodule KlassHero.EventSubscriberWiringTest do
  @moduledoc """
  Guards the gap between what a handler says it handles and what its subscriber
  is actually subscribed to.

  `EventSubscriber` subscribes off the literal `topics:` list it is given and
  never consults `subscribed_events/0`. So adding a clause to a handler without
  extending its topic list produces a handler that compiles, reads correctly and
  silently never fires — indistinguishable from a feature that does nothing.
  """

  use ExUnit.Case, async: true

  defp subscriber_wiring do
    for spec <- KlassHero.Application.integration_event_subscribers(),
        {_module, _fun, [opts]} = spec.start,
        handler = Keyword.fetch!(opts, :handler),
        topics = Keyword.fetch!(opts, :topics) do
      {spec.id, handler, topics}
    end
  end

  # "integration:<context>:<event>" — the event is the last segment.
  defp event_from_topic(topic) do
    topic |> String.split(":") |> List.last() |> String.to_existing_atom()
  end

  test "every subscriber is subscribed to a topic for each event its handler declares" do
    for {id, handler, topics} <- subscriber_wiring() do
      subscribed = MapSet.new(handler.subscribed_events())
      reachable = MapSet.new(topics, &event_from_topic/1)
      unreachable = MapSet.difference(subscribed, reachable)

      assert Enum.empty?(unreachable),
             """
             #{inspect(id)} (#{inspect(handler)}) declares events it can never receive: \
             #{inspect(MapSet.to_list(unreachable))}
             Add the matching "integration:<context>:<event>" topic to its child spec \
             in KlassHero.Application, or drop the handler clause.
             """
    end
  end

  test "every subscribed topic maps to an event the handler declares" do
    for {id, handler, topics} <- subscriber_wiring() do
      subscribed = MapSet.new(handler.subscribed_events())
      unhandled = topics |> MapSet.new(&event_from_topic/1) |> MapSet.difference(subscribed)

      assert Enum.empty?(unhandled),
             """
             #{inspect(id)} (#{inspect(handler)}) subscribes to topics its handler ignores: \
             #{inspect(MapSet.to_list(unhandled))}
             """
    end
  end
end
