defmodule KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisherTest do
  @moduledoc """
  Covers the topic-recording added for #1122: the integration-event test double
  now captures the `integration:<context>:<event>` topic each event is routed on,
  so tests can assert the producer/consumer coupling of the
  `critical_event_handlers` registry instead of pinning topic literals by hand.
  Mirrors the domain-event double covered by #1108.
  """
  use ExUnit.Case, async: true

  alias KlassHero.EventTestHelper
  alias KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  setup do
    TestIntegrationEventPublisher.setup()
    :ok
  end

  test "publish/2 records the event with the topic it was published to" do
    event = IntegrationEvent.new(:invite_claimed, :enrollment, :invite, "invite-1", %{})

    TestIntegrationEventPublisher.publish(event, "integration:enrollment:invite_claimed")

    assert TestIntegrationEventPublisher.get_published() ==
             [{event, "integration:enrollment:invite_claimed"}]
  end

  test "publish/1 records the event with its derived topic" do
    event = IntegrationEvent.new(:invite_claimed, :enrollment, :invite, "invite-1", %{})

    TestIntegrationEventPublisher.publish(event)

    assert TestIntegrationEventPublisher.get_published() ==
             [{event, "integration:enrollment:invite_claimed"}]
  end

  test "get_events/0 still returns bare events (backward compatible)" do
    event = IntegrationEvent.new(:user_registered, :accounts, :user, "user-1", %{})

    TestIntegrationEventPublisher.publish(event)

    assert TestIntegrationEventPublisher.get_events() == [event]
  end

  describe "EventTestHelper.assert_integration_published_to/2" do
    test "passes when the event was published to the topic" do
      event = IntegrationEvent.new(:invite_claimed, :enrollment, :invite, "invite-1", %{})
      TestIntegrationEventPublisher.publish(event)

      assert EventTestHelper.assert_integration_published_to(
               :invite_claimed,
               "integration:enrollment:invite_claimed"
             ) == event
    end

    test "fails when the event went to a different topic" do
      event = IntegrationEvent.new(:invite_claimed, :enrollment, :invite, "invite-1", %{})
      TestIntegrationEventPublisher.publish(event, "integration:enrolment:invite_claimed")

      assert_raise ExUnit.AssertionError, fn ->
        EventTestHelper.assert_integration_published_to(
          :invite_claimed,
          "integration:enrollment:invite_claimed"
        )
      end
    end
  end
end
