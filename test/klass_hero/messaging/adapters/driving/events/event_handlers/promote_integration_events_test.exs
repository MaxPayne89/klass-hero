defmodule KlassHero.Messaging.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEventsTest do
  use ExUnit.Case, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.Messaging.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents
  alias KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  setup do
    setup_test_integration_events()
    :ok
  end

  # Messaging promotions vary along more axes than the other contexts, so each is
  # a full table row: the published event type (usually the domain type, but
  # user_data_anonymized renames to message_data_anonymized), aggregate type, the
  # payload, whether a publish failure is swallowed (:ok) or propagated
  # ({:error, reason}), and the per-event entity_type/criticality/payload checks.
  @cases [
    %{
      type: :user_data_anonymized,
      published: :message_data_anonymized,
      agg: :user,
      id: "user-1",
      payload: %{user_id: "user-1"},
      mode: :swallow,
      critical: true
    },
    %{
      type: :conversation_created,
      agg: :conversation,
      id: "conv-1",
      entity_type: :conversation,
      payload: %{conversation_id: "conv-1", type: :direct, provider_id: "pv-1", participant_ids: ["u1", "u2"]},
      mode: :propagate
    },
    %{
      type: :message_sent,
      agg: :conversation,
      id: "conv-1",
      payload: %{
        conversation_id: "conv-1",
        message_id: "msg-1",
        sender_id: "s-1",
        content: "Hello!",
        message_type: :text,
        sent_at: ~U[2026-01-01 00:00:00Z]
      },
      mode: :propagate,
      checks: [content: "Hello!"]
    },
    %{
      type: :messages_read,
      agg: :conversation,
      id: "conv-1",
      payload: %{conversation_id: "conv-1", user_id: "user-1", read_at: ~U[2026-01-01 00:00:00Z]},
      mode: :swallow,
      checks: [user_id: "user-1"]
    },
    %{
      type: :conversation_archived,
      agg: :conversation,
      id: "conv-1",
      payload: %{conversation_id: "conv-1", reason: :program_ended},
      mode: :swallow
    },
    %{
      type: :conversations_archived,
      agg: :conversation,
      id: "bulk_archive_123",
      payload: %{conversation_ids: ["c1", "c2"], reason: :program_ended, count: 2},
      mode: :swallow,
      checks: [count: 2]
    },
    %{
      type: :participant_added,
      agg: :conversation,
      id: "conv-1",
      entity_type: :conversation,
      critical: true,
      payload: %{conversation_id: "conv-1", participant_user_ids: ["u1", "u2"], source: :initial_staff},
      mode: :propagate,
      checks: [participant_user_ids: ["u1", "u2"], source: "initial_staff"]
    },
    %{
      type: :participant_removed,
      agg: :conversation,
      id: "conv-1",
      entity_type: :conversation,
      critical: true,
      payload: %{conversation_id: "conv-1", participant_user_ids: ["u1"], source: :staff_unassignment},
      mode: :propagate,
      checks: [participant_user_ids: ["u1"], source: "staff_unassignment"]
    }
  ]

  for spec <- @cases do
    describe "handle/1 — #{spec.type}" do
      @type_ spec.type
      @published Map.get(spec, :published, spec.type)
      @agg spec.agg
      @id spec.id
      @payload spec.payload
      @mode spec.mode
      @entity_type Map.get(spec, :entity_type)
      @critical Map.get(spec, :critical, false)
      @checks Map.get(spec, :checks, [])

      test "promotes to the #{Map.get(spec, :published, spec.type)} integration event" do
        domain_event = DomainEvent.new(@type_, @id, @agg, @payload)

        assert :ok = PromoteIntegrationEvents.handle(domain_event)

        event = assert_integration_event_published(@published)
        assert event.entity_id == @id
        assert event.source_context == :messaging
        if @entity_type, do: assert(event.entity_type == @entity_type)
        if @critical, do: assert(IntegrationEvent.critical?(event))
        Enum.each(@checks, fn {key, value} -> assert Map.get(event.payload, key) == value end)
      end

      test "#{spec.mode}s publish failures" do
        domain_event = DomainEvent.new(@type_, @id, @agg, @payload)
        TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

        case @mode do
          :swallow ->
            assert :ok = PromoteIntegrationEvents.handle(domain_event)
            assert_no_integration_events_published()

          :propagate ->
            assert {:error, :pubsub_down} = PromoteIntegrationEvents.handle(domain_event)
        end
      end
    end
  end
end
