defmodule KlassHero.EventConsumerWiringTest do
  @moduledoc """
  Guards the gap between what a consumer says it consumes and what the registry
  actually routes to it.

  Nothing consults a handler's `subscribed_events/0` or a projection's `topics/0`
  at runtime — delivery goes off `:event_consumers` alone. So adding a clause to a
  consumer without adding the matching registry entry produces code that compiles,
  reads correctly and silently never runs, which is indistinguishable from a
  feature that does nothing. That failure mode is how six projections ended up
  with no durable delivery path at all.
  """

  use ExUnit.Case, async: true

  alias KlassHero.ProjectionSupervisor
  alias KlassHero.Shared.Adapters.Driven.Events.EventConsumerRegistry

  defp registry, do: Application.fetch_env!(:klass_hero, :event_consumers)

  defp topics_routed_to(module) do
    for {topic, consumers} <- registry(),
        {^module, _fun} <- consumers,
        do: topic
  end

  # "integration:<context>:<event>" — the event is the last segment.
  defp event_from_topic(topic), do: topic |> String.split(":") |> List.last() |> String.to_existing_atom()

  defp handlers do
    registry()
    |> Enum.flat_map(fn {_topic, consumers} -> Enum.map(consumers, &elem(&1, 0)) end)
    |> Enum.uniq()
    |> Enum.reject(&(&1 in ProjectionSupervisor.projections()))
  end

  describe "handlers" do
    test "every event a handler declares is routed to it" do
      for handler <- handlers() do
        declared = MapSet.new(handler.subscribed_events())
        routed = handler |> topics_routed_to() |> MapSet.new(&event_from_topic/1)
        unreachable = MapSet.difference(declared, routed)

        assert Enum.empty?(unreachable),
               """
               #{inspect(handler)} declares events it can never receive: \
               #{inspect(MapSet.to_list(unreachable))}
               Add the matching "integration:<context>:<event>" key to :event_consumers \
               in config/config.exs, or drop the handler clause.
               """
      end
    end

    test "every topic routed to a handler maps to an event it declares" do
      for handler <- handlers() do
        declared = MapSet.new(handler.subscribed_events())
        unhandled = handler |> topics_routed_to() |> MapSet.new(&event_from_topic/1) |> MapSet.difference(declared)

        assert Enum.empty?(unhandled),
               "#{inspect(handler)} is routed topics it ignores: #{inspect(MapSet.to_list(unhandled))}"
      end
    end
  end

  describe "projections" do
    test "every integration topic a projection declares is routed to it" do
      for projection <- ProjectionSupervisor.projections() do
        declared = projection.topics() |> Enum.filter(&String.starts_with?(&1, "integration:")) |> MapSet.new()
        unreachable = MapSet.difference(declared, MapSet.new(topics_routed_to(projection)))

        assert Enum.empty?(unreachable),
               """
               #{inspect(projection)} declares topics nothing routes to it: \
               #{inspect(MapSet.to_list(unreachable))}
               Its read table would silently stop updating for those events.
               """
      end
    end

    test "every topic routed to a projection is one it declares" do
      for projection <- ProjectionSupervisor.projections() do
        declared = MapSet.new(projection.topics())
        unhandled = projection |> topics_routed_to() |> MapSet.new() |> MapSet.difference(declared)

        assert Enum.empty?(unhandled),
               "#{inspect(projection)} is routed topics it ignores: #{inspect(MapSet.to_list(unhandled))}"
      end
    end
  end

  describe "the registry itself" do
    test "every consumer names a function that exists and takes the event" do
      for {topic, consumers} <- registry(), {module, fun} <- consumers do
        Code.ensure_loaded!(module)

        assert function_exported?(module, fun, 1),
               "#{topic} routes to #{inspect(module)}.#{fun}/1, which is not exported"
      end
    end

    test "every topic reads integration:<context>:<event>" do
      for topic <- EventConsumerRegistry.topics() do
        assert [_, _, _] = String.split(topic, ":"),
               "#{topic} is not an integration event topic"

        assert String.starts_with?(topic, "integration:")
      end
    end

    # Temporary, for the length of this PR: :critical_event_handlers still drives the
    # old PubSub-plus-Oban path while producers are migrated. Delete with that config.
    test "the superseded critical-handler map stays a subset of the registry" do
      for {topic, handlers} <- Application.fetch_env!(:klass_hero, :critical_event_handlers), handler <- handlers do
        assert handler in EventConsumerRegistry.consumers_for(topic),
               "#{topic} routes to #{inspect(handler)} in :critical_event_handlers but not in :event_consumers"
      end
    end
  end
end
