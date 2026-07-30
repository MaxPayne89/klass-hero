defmodule KlassHero.EventTestHelper do
  @moduledoc """
  Test helpers for asserting on the integration events a write emitted.

      setup do
        KlassHero.EventTestHelper.setup_test_integration_events()
        :ok
      end

      test "staging an event" do
        {:ok, user} = Accounts.register_user(attrs)

        assert_integration_event_published(:user_registered)
        assert_integration_event_published(:user_registered, %{email: user.email})
      end

  The domain-event half of this module is gone: LiveViews receive tagged tuples
  now, so a test that wants to drive one `send/2`s the tuple, and a test that
  wants to check a notification subscribes to the topic and asserts on the
  message. Neither needs a helper.
  """

  import ExUnit.Assertions

  alias KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher
  alias KlassHero.Shared.Adapters.Driven.Events.TestOutbox
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  # ===========================================================================
  # Integration Event Unit Test Helpers (TestIntegrationEventPublisher)
  # ===========================================================================

  @doc """
  Initializes integration event collection for the current test.

  Call this in your test setup block.
  """
  @spec setup_test_integration_events() :: :ok
  def setup_test_integration_events do
    TestIntegrationEventPublisher.setup()
    TestOutbox.setup()
  end

  @doc """
  Clears all collected integration events.
  """
  @spec clear_integration_events() :: :ok
  def clear_integration_events do
    TestIntegrationEventPublisher.clear()
    TestOutbox.setup()
  end

  @doc """
  Every integration event the code under test emitted, by either route.

  A producer either publishes post-commit (the old path) or stages inside its
  transaction (the outbox). Both mean the same thing to a test — *this write emitted
  this event* — so both are collected here while contexts are migrated one at a
  time. The publisher half goes when the last producer moves.
  """
  @spec get_published_integration_events() :: [IntegrationEvent.t()]
  def get_published_integration_events do
    TestIntegrationEventPublisher.get_events() ++ TestOutbox.staged()
  end

  @doc """
  Asserts that an integration event of the given type was published.

  ## Examples

      assert_integration_event_published(:child_data_anonymized)
  """
  @spec assert_integration_event_published(atom()) :: IntegrationEvent.t()
  def assert_integration_event_published(event_type) when is_atom(event_type) do
    events = get_published_integration_events()

    event =
      Enum.find(events, fn %IntegrationEvent{event_type: type} ->
        type == event_type
      end)

    assert event != nil,
           "Expected integration event #{inspect(event_type)} to be published.\n" <>
             "Published integration events: #{format_event_types(events)}"

    event
  end

  @doc """
  Asserts that an integration event of the given type was published with a payload
  matching the expected fields.

  The payload match is partial - only the specified fields are checked.

  ## Examples

      assert_integration_event_published(:child_data_anonymized, %{child_id: "uuid"})
  """
  @spec assert_integration_event_published(atom(), map()) :: IntegrationEvent.t()
  def assert_integration_event_published(event_type, expected_payload)
      when is_atom(event_type) and is_map(expected_payload) do
    events = get_published_integration_events()

    event =
      Enum.find(events, fn %IntegrationEvent{event_type: type, payload: payload} ->
        type == event_type && payload_matches?(payload, expected_payload)
      end)

    if event == nil do
      matching_type_events =
        Enum.filter(events, fn %IntegrationEvent{event_type: type} ->
          type == event_type
        end)

      if matching_type_events == [] do
        flunk(
          "Expected integration event #{inspect(event_type)} to be published.\n" <>
            "Published integration events: #{format_event_types(events)}"
        )
      else
        flunk(
          "Expected integration event #{inspect(event_type)} with payload matching:\n" <>
            "  #{inspect(expected_payload)}\n\n" <>
            "Found #{length(matching_type_events)} event(s) of type #{inspect(event_type)}:\n" <>
            format_event_payloads(matching_type_events)
        )
      end
    end

    event
  end

  @doc """
  Asserts that an integration event of the given type was published to `topic`.

  Proves the real producer/consumer topic coupling (#1122): the topic recorded
  here is the exact `integration:<context>:<event>` string the event was routed
  on, so the `critical_event_handlers` registry entry keyed by `topic` would have
  received it. Returns the matching event.

  ## Examples

      assert_integration_published_to(:invite_claimed, "integration:enrollment:invite_claimed")
  """
  @spec assert_integration_published_to(atom(), String.t()) :: IntegrationEvent.t()
  def assert_integration_published_to(event_type, topic) when is_atom(event_type) and is_binary(topic) do
    published = TestIntegrationEventPublisher.get_published() ++ staged_with_topics()

    match =
      Enum.find(published, fn {%IntegrationEvent{event_type: type}, published_topic} ->
        type == event_type and published_topic == topic
      end)

    assert match != nil,
           "Expected integration event #{inspect(event_type)} to be published to #{inspect(topic)}.\n" <>
             "Published: #{format_published(published)}"

    {event, _topic} = match
    event
  end

  # Staged events carry no topic of their own — the delivery job derives it the same
  # way the publisher did, so deriving it here compares like with like.
  defp staged_with_topics do
    for %IntegrationEvent{source_context: context, event_type: type} = event <- TestOutbox.staged() do
      {event, "integration:#{context}:#{type}"}
    end
  end

  @doc """
  Asserts that no integration events were published.
  """
  @spec assert_no_integration_events_published() :: :ok
  def assert_no_integration_events_published do
    events = get_published_integration_events()

    assert events == [],
           "Expected no integration events to be published.\n" <>
             "Published integration events: #{format_event_types(events)}"

    :ok
  end

  @doc """
  Asserts that exactly the given number of integration events were published.
  """
  @spec assert_integration_event_count(non_neg_integer()) :: :ok
  def assert_integration_event_count(expected_count) when is_integer(expected_count) do
    events = get_published_integration_events()
    actual_count = length(events)

    assert actual_count == expected_count,
           "Expected #{expected_count} integration event(s) to be published, but got #{actual_count}.\n" <>
             "Published integration events: #{format_event_types(events)}"

    :ok
  end

  defp payload_matches?(actual, expected) do
    Enum.all?(expected, fn {key, value} ->
      Map.get(actual, key) == value
    end)
  end

  defp format_event_types([]), do: "(none)"
  defp format_event_types(events), do: Enum.map_join(events, ", ", &inspect(&1.event_type))

  defp format_published([]), do: "(none)"

  defp format_published(published) do
    Enum.map_join(published, ", ", fn {event, topic} ->
      "#{inspect(event.event_type)}→#{inspect(topic)}"
    end)
  end

  defp format_event_payloads(events) do
    events
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {event, idx} -> "  #{idx}. #{inspect(event.payload)}" end)
  end
end
