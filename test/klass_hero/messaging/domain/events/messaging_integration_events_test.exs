defmodule KlassHero.Messaging.Domain.Events.MessagingIntegrationEventsTest do
  @moduledoc """
  Tests for MessagingIntegrationEvents factory module.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Messaging.Domain.Events.MessagingIntegrationEvents, as: Events
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  # Most Messaging integration-event factories share one contract: build an
  # event with stable identity fields, let the base payload's id win over any
  # caller-supplied id (while preserving extras), and raise on a blank id.
  # Rows vary by the id field name, entity_type, whether the factory is
  # critical, and which extra payload keys it requires. `conversations_archived`
  # breaks the base-id-wins contract (it passes its payload straight through)
  # and uses a different id field name, so it's handled entirely as
  # hand-written tests below, alongside message_data_anonymized's criticality
  # override and the participant_* factories' extra "empty list" and
  # source-scalarization coverage.
  @factories [
    %{fun: :message_data_anonymized, id: :user_id, entity: :user, critical: true},
    %{
      fun: :conversation_created,
      id: :conversation_id,
      entity: :conversation,
      required: [:participant_ids, :provider_id],
      extra_payload: %{participant_ids: ["p1", "p2"], provider_id: "provider-1"}
    },
    %{
      fun: :message_sent,
      id: :conversation_id,
      entity: :conversation,
      required: [:sender_id],
      extra_payload: %{sender_id: "sender-1", content: "Hello"}
    },
    %{
      fun: :messages_read,
      id: :conversation_id,
      entity: :conversation,
      required: [:user_id],
      extra_payload: %{user_id: "user-1"}
    },
    %{fun: :conversation_archived, id: :conversation_id, entity: :conversation},
    %{
      fun: :participant_added,
      id: :conversation_id,
      entity: :conversation,
      critical: true,
      required: [:participant_user_ids, :source],
      extra_payload: %{participant_user_ids: ["u1"], source: :initial_staff},
      invalid_payloads: [%{}, %{participant_user_ids: ["u1"]}, %{source: :initial_staff}]
    },
    %{
      fun: :participant_removed,
      id: :conversation_id,
      entity: :conversation,
      critical: true,
      required: [:participant_user_ids, :source],
      extra_payload: %{participant_user_ids: ["u1"], source: :staff_unassignment},
      invalid_payloads: [%{}, %{participant_user_ids: ["u1"]}, %{source: :staff_unassignment}]
    }
  ]

  for spec <- @factories do
    describe "#{spec.fun}/3" do
      @fun spec.fun
      @id spec.id
      @entity spec.entity
      @critical Map.get(spec, :critical, false)
      @required Map.get(spec, :required, [])
      @extra_payload Map.get(spec, :extra_payload, %{})
      @invalid_payloads Map.get(spec, :invalid_payloads, [%{}])

      test "creates event with correct type, source_context, and entity_type" do
        event = apply(Events, @fun, ["id-1", @extra_payload])

        assert event.event_type == @fun
        assert event.source_context == :messaging
        assert event.entity_type == @entity
        assert event.entity_id == "id-1"
      end

      test "base_payload id wins over caller-supplied and preserves extras" do
        payload = Map.merge(@extra_payload, %{@id => "overridden", extra: "data"})
        event = apply(Events, @fun, ["real-id", payload])

        assert Map.get(event.payload, @id) == "real-id"
        assert event.payload.extra == "data"
      end

      test "raises for a nil or blank id" do
        for bad_id <- [nil, ""] do
          assert_raise ArgumentError, ~r/requires a non-empty #{@id} string/, fn ->
            apply(Events, @fun, [bad_id, @extra_payload])
          end
        end
      end

      if @critical do
        test "marks event as critical by default" do
          event = apply(Events, @fun, ["id-1", @extra_payload])

          assert IntegrationEvent.critical?(event)
        end
      end

      if @required != [] do
        test "raises when required payload keys are missing" do
          for payload <- @invalid_payloads do
            assert_raise ArgumentError, ~r/#{@fun} missing required payload keys/, fn ->
              apply(Events, @fun, ["id-1", payload])
            end
          end
        end
      end
    end
  end

  describe "message_data_anonymized/3 criticality override" do
    test "allows overriding criticality via opts" do
      event = Events.message_data_anonymized("user-1", %{}, criticality: :normal)

      refute IntegrationEvent.critical?(event)
    end
  end

  describe "participant_added/3 payload passthrough" do
    test "converts source atom to string and preserves participant_user_ids" do
      event =
        Events.participant_added("conv-1", %{
          participant_user_ids: ["staff-1"],
          source: :later_assignment
        })

      assert event.payload.participant_user_ids == ["staff-1"]
      assert event.payload.source == "later_assignment"
    end

    test "raises when participant_user_ids is empty" do
      assert_raise ArgumentError, ~r/participant_added requires a non-empty participant_user_ids list/, fn ->
        Events.participant_added("conv-1", %{participant_user_ids: [], source: :initial_staff})
      end
    end
  end

  describe "participant_removed/3 payload passthrough" do
    test "converts source atom to string and preserves participant_user_ids" do
      event =
        Events.participant_removed("conv-1", %{
          participant_user_ids: ["staff-1"],
          source: :staff_unassignment
        })

      assert event.payload.participant_user_ids == ["staff-1"]
      assert event.payload.source == "staff_unassignment"
    end

    test "raises when participant_user_ids is empty" do
      assert_raise ArgumentError, ~r/participant_removed requires a non-empty participant_user_ids list/, fn ->
        Events.participant_removed("conv-1", %{participant_user_ids: [], source: :staff_unassignment})
      end
    end
  end

  describe "conversations_archived/3" do
    test "creates event with correct type, source_context, and entity_type" do
      event =
        Events.conversations_archived("bulk_archive_123", %{conversation_ids: ["c1", "c2"]})

      assert event.event_type == :conversations_archived
      assert event.source_context == :messaging
      assert event.entity_type == :conversation
      assert event.entity_id == "bulk_archive_123"
    end

    test "passes payload directly without merging base_payload" do
      payload = %{conversation_ids: ["c1", "c2"], reason: "program_ended"}

      event = Events.conversations_archived("bulk_archive_123", payload)

      assert event.payload == payload
    end

    test "raises when required payload keys are missing" do
      assert_raise ArgumentError, ~r/conversations_archived missing required payload keys/, fn ->
        Events.conversations_archived("bulk_archive_123", %{})
      end
    end

    test "raises for a nil or blank aggregate_id" do
      valid_payload = %{conversation_ids: ["c1"]}

      for bad_id <- [nil, ""] do
        assert_raise ArgumentError, ~r/requires a non-empty aggregate_id string/, fn ->
          Events.conversations_archived(bad_id, valid_payload)
        end
      end
    end
  end
end
