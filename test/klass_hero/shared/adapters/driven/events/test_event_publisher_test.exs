defmodule KlassHero.Shared.Adapters.Driven.Events.TestEventPublisherTest do
  @moduledoc """
  Covers the topic-recording added for #1108: the test double now captures the
  topic passed to `publish/2`, so tests can assert the real publish→subscribe
  coupling instead of pinning topic literals by hand.
  """
  use ExUnit.Case, async: true

  alias KlassHero.EventTestHelper
  alias KlassHero.Shared.Adapters.Driven.Events.TestEventPublisher
  alias KlassHero.Shared.Domain.Events.DomainEvent

  setup do
    TestEventPublisher.setup()
    :ok
  end

  test "publish/2 records the event with the topic it was published to" do
    event = DomainEvent.new(:session_note_submitted, "note-1", :session_note, %{})

    TestEventPublisher.publish(event, "session_note:session_note_submitted")

    assert TestEventPublisher.get_published() == [{event, "session_note:session_note_submitted"}]
  end

  test "get_events/0 still returns bare events (backward compatible)" do
    event = DomainEvent.new(:child_checked_in, "rec-1", :participation, %{})

    TestEventPublisher.publish(event, "participation:child_checked_in")

    assert TestEventPublisher.get_events() == [event]
  end

  describe "EventTestHelper.assert_published_to/2" do
    test "passes when the event was published to the topic" do
      event = DomainEvent.new(:child_checked_in, "rec-1", :participation, %{})
      TestEventPublisher.publish(event, "participation:child_checked_in")

      assert EventTestHelper.assert_published_to(:child_checked_in, "participation:child_checked_in") ==
               event
    end

    test "fails when the event went to a different topic" do
      event = DomainEvent.new(:child_checked_in, "rec-1", :participation, %{})
      TestEventPublisher.publish(event, "participation_record:child_checked_in")

      assert_raise ExUnit.AssertionError, fn ->
        EventTestHelper.assert_published_to(:child_checked_in, "participation:child_checked_in")
      end
    end
  end
end
