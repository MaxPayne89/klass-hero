defmodule KlassHero.Participation.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEventsTest do
  use ExUnit.Case, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.Participation.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents
  alias KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher
  alias KlassHero.Shared.Domain.Events.DomainEvent

  setup do
    setup_test_integration_events()
    :ok
  end

  # Every handler clause shares one contract: read the id from the domain event's
  # aggregate_id, hand the payload to the matching factory, and publish best-effort
  # (publish failures are swallowed to :ok). The table drives that shape; each row
  # is (event_type, aggregate_type, required payload). session_cancelled's payload
  # passthrough is the one factory-specific assertion, kept below the table.
  @cases [
    %{
      type: :session_created,
      agg: :participation,
      payload: %{program_id: "prog-1", session_date: ~D[2026-04-01], start_time: ~T[09:00:00], end_time: ~T[10:00:00]}
    },
    %{type: :session_started, agg: :participation, payload: %{program_id: "prog-1"}},
    %{
      type: :session_completed,
      agg: :participation,
      payload: %{program_id: "prog-1", provider_id: "pv-1", program_title: "Art Class"}
    },
    %{type: :session_cancelled, agg: :participation, payload: %{program_id: "prog-1"}},
    %{type: :roster_seeded, agg: :participation, payload: %{program_id: "prog-1", seeded_count: 3}},
    %{type: :child_checked_in, agg: :participation, payload: %{session_id: "sess-1", child_id: "child-1"}},
    %{type: :child_checked_out, agg: :participation, payload: %{session_id: "sess-1", child_id: "child-1"}},
    %{type: :child_marked_absent, agg: :participation, payload: %{session_id: "sess-1", child_id: "child-1"}},
    %{
      type: :session_note_submitted,
      agg: :session_note,
      payload: %{participation_record_id: "pr-1", child_id: "child-1", provider_id: "pv-1"}
    },
    %{
      type: :session_note_approved,
      agg: :session_note,
      payload: %{participation_record_id: "pr-1", child_id: "child-1", provider_id: "pv-1"}
    },
    %{
      type: :session_note_rejected,
      agg: :session_note,
      payload: %{participation_record_id: "pr-1", child_id: "child-1", provider_id: "pv-1"}
    }
  ]

  for %{type: type, agg: agg, payload: payload} <- @cases do
    describe "handle/1 — #{type}" do
      @type_ type
      @agg agg
      @payload payload

      test "promotes to the #{type} integration event" do
        domain_event = DomainEvent.new(@type_, "id-1", @agg, @payload)

        assert :ok = PromoteIntegrationEvents.handle(domain_event)

        event = assert_integration_event_published(@type_)
        assert event.entity_id == "id-1"
        assert event.source_context == :participation
      end

      test "swallows publish failures with :ok" do
        domain_event = DomainEvent.new(@type_, "id-1", @agg, @payload)
        TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

        assert :ok = PromoteIntegrationEvents.handle(domain_event)
        assert_no_integration_events_published()
      end
    end
  end

  describe "handle/1 — :session_cancelled payload" do
    test "carries program_id through to the integration event" do
      domain_event = DomainEvent.new(:session_cancelled, "id-1", :participation, %{program_id: "prog-1"})

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:session_cancelled)
      assert event.payload.program_id == "prog-1"
    end
  end
end
