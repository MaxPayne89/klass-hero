defmodule KlassHero.Messaging.Domain.Events.MessagingIntegrationEventsTest do
  @moduledoc """
  Tests for MessagingIntegrationEvents factory module.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Messaging.Domain.Events.MessagingIntegrationEvents
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  describe "message_data_anonymized/3" do
    test "creates event with correct type, source_context, and entity_type" do
      user_id = Ecto.UUID.generate()

      event = MessagingIntegrationEvents.message_data_anonymized(user_id)

      assert event.event_type == :message_data_anonymized
      assert event.source_context == :messaging
      assert event.entity_type == :user
      assert event.entity_id == user_id
    end

    test "base_payload user_id wins over caller-supplied user_id" do
      real_id = Ecto.UUID.generate()
      conflicting_payload = %{user_id: "should-be-overridden", extra: "data"}

      event = MessagingIntegrationEvents.message_data_anonymized(real_id, conflicting_payload)

      assert event.payload.user_id == real_id
      assert event.payload.extra == "data"
    end

    test "marks event as critical by default" do
      user_id = Ecto.UUID.generate()

      event = MessagingIntegrationEvents.message_data_anonymized(user_id)

      assert IntegrationEvent.critical?(event)
    end

    test "allows overriding criticality via opts" do
      user_id = Ecto.UUID.generate()

      event =
        MessagingIntegrationEvents.message_data_anonymized(user_id, %{}, criticality: :normal)

      refute IntegrationEvent.critical?(event)
    end

    test "raises for nil user_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty user_id string/,
                   fn -> MessagingIntegrationEvents.message_data_anonymized(nil) end
    end

    test "raises for empty string user_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty user_id string/,
                   fn -> MessagingIntegrationEvents.message_data_anonymized("") end
    end
  end

  describe "conversation_created/3" do
    test "creates event with correct type, source_context, and entity_type" do
      conversation_id = Ecto.UUID.generate()

      event =
        MessagingIntegrationEvents.conversation_created(conversation_id, %{
          participant_ids: ["p1", "p2"],
          provider_id: Ecto.UUID.generate()
        })

      assert event.event_type == :conversation_created
      assert event.source_context == :messaging
      assert event.entity_type == :conversation
      assert event.entity_id == conversation_id
    end

    test "base_payload conversation_id wins over caller-supplied" do
      real_id = Ecto.UUID.generate()

      event =
        MessagingIntegrationEvents.conversation_created(real_id, %{
          conversation_id: "should-be-overridden",
          participant_ids: ["p1", "p2"],
          provider_id: Ecto.UUID.generate(),
          extra: "data"
        })

      assert event.payload.conversation_id == real_id
      assert event.payload.extra == "data"
    end

    test "raises when required payload keys are missing" do
      conversation_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/conversation_created missing required payload keys/,
                   fn ->
                     MessagingIntegrationEvents.conversation_created(conversation_id, %{})
                   end
    end

    test "raises for nil or empty conversation_id" do
      valid_payload = %{participant_ids: ["p1"], provider_id: Ecto.UUID.generate()}

      assert_raise ArgumentError,
                   ~r/requires a non-empty conversation_id string/,
                   fn -> MessagingIntegrationEvents.conversation_created(nil, valid_payload) end

      assert_raise ArgumentError,
                   ~r/requires a non-empty conversation_id string/,
                   fn -> MessagingIntegrationEvents.conversation_created("", valid_payload) end
    end
  end

  describe "message_sent/3" do
    test "creates event with correct type, source_context, and entity_type" do
      conversation_id = Ecto.UUID.generate()

      event =
        MessagingIntegrationEvents.message_sent(conversation_id, %{
          sender_id: Ecto.UUID.generate(),
          content: "Hello"
        })

      assert event.event_type == :message_sent
      assert event.source_context == :messaging
      assert event.entity_type == :conversation
      assert event.entity_id == conversation_id
    end

    test "base_payload conversation_id wins over caller-supplied" do
      real_id = Ecto.UUID.generate()

      event =
        MessagingIntegrationEvents.message_sent(real_id, %{
          conversation_id: "should-be-overridden",
          sender_id: Ecto.UUID.generate(),
          content: "Hello",
          extra: "data"
        })

      assert event.payload.conversation_id == real_id
      assert event.payload.extra == "data"
    end

    test "raises when required payload keys are missing" do
      conversation_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/message_sent missing required payload keys/,
                   fn ->
                     MessagingIntegrationEvents.message_sent(conversation_id, %{})
                   end
    end

    test "raises for nil or empty conversation_id" do
      valid_payload = %{sender_id: Ecto.UUID.generate(), content: "Hello"}

      assert_raise ArgumentError,
                   ~r/requires a non-empty conversation_id string/,
                   fn -> MessagingIntegrationEvents.message_sent(nil, valid_payload) end

      assert_raise ArgumentError,
                   ~r/requires a non-empty conversation_id string/,
                   fn -> MessagingIntegrationEvents.message_sent("", valid_payload) end
    end
  end

  describe "messages_read/3" do
    test "creates event with correct type, source_context, and entity_type" do
      conversation_id = Ecto.UUID.generate()

      event =
        MessagingIntegrationEvents.messages_read(conversation_id, %{
          user_id: Ecto.UUID.generate()
        })

      assert event.event_type == :messages_read
      assert event.source_context == :messaging
      assert event.entity_type == :conversation
      assert event.entity_id == conversation_id
    end

    test "base_payload conversation_id wins over caller-supplied" do
      real_id = Ecto.UUID.generate()

      event =
        MessagingIntegrationEvents.messages_read(real_id, %{
          conversation_id: "should-be-overridden",
          user_id: Ecto.UUID.generate(),
          extra: "data"
        })

      assert event.payload.conversation_id == real_id
      assert event.payload.extra == "data"
    end

    test "raises when required payload keys are missing" do
      conversation_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/messages_read missing required payload keys/,
                   fn ->
                     MessagingIntegrationEvents.messages_read(conversation_id, %{})
                   end
    end

    test "raises for nil or empty conversation_id" do
      valid_payload = %{user_id: Ecto.UUID.generate()}

      assert_raise ArgumentError,
                   ~r/requires a non-empty conversation_id string/,
                   fn -> MessagingIntegrationEvents.messages_read(nil, valid_payload) end

      assert_raise ArgumentError,
                   ~r/requires a non-empty conversation_id string/,
                   fn -> MessagingIntegrationEvents.messages_read("", valid_payload) end
    end
  end

  describe "conversation_archived/3" do
    test "creates event with correct type, source_context, and entity_type" do
      conversation_id = Ecto.UUID.generate()

      event = MessagingIntegrationEvents.conversation_archived(conversation_id)

      assert event.event_type == :conversation_archived
      assert event.source_context == :messaging
      assert event.entity_type == :conversation
      assert event.entity_id == conversation_id
    end

    test "base_payload conversation_id wins over caller-supplied" do
      real_id = Ecto.UUID.generate()

      event =
        MessagingIntegrationEvents.conversation_archived(real_id, %{
          conversation_id: "should-be-overridden",
          reason: "program_ended"
        })

      assert event.payload.conversation_id == real_id
      assert event.payload.reason == "program_ended"
    end

    test "raises for nil or empty conversation_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty conversation_id string/,
                   fn -> MessagingIntegrationEvents.conversation_archived(nil) end

      assert_raise ArgumentError,
                   ~r/requires a non-empty conversation_id string/,
                   fn -> MessagingIntegrationEvents.conversation_archived("") end
    end
  end

  describe "conversations_archived/3" do
    test "creates event with correct type, source_context, and entity_type" do
      aggregate_id = "bulk_archive_123"

      event =
        MessagingIntegrationEvents.conversations_archived(aggregate_id, %{
          conversation_ids: ["c1", "c2"]
        })

      assert event.event_type == :conversations_archived
      assert event.source_context == :messaging
      assert event.entity_type == :conversation
      assert event.entity_id == aggregate_id
    end

    test "passes payload directly without merging base_payload" do
      aggregate_id = "bulk_archive_123"
      payload = %{conversation_ids: ["c1", "c2"], reason: "program_ended"}

      event = MessagingIntegrationEvents.conversations_archived(aggregate_id, payload)

      assert event.payload == payload
    end

    test "raises when required payload keys are missing" do
      aggregate_id = "bulk_archive_123"

      assert_raise ArgumentError,
                   ~r/conversations_archived missing required payload keys/,
                   fn ->
                     MessagingIntegrationEvents.conversations_archived(aggregate_id, %{})
                   end
    end

    test "raises for nil or empty aggregate_id" do
      valid_payload = %{conversation_ids: ["c1"]}

      assert_raise ArgumentError,
                   ~r/requires a non-empty aggregate_id string/,
                   fn ->
                     MessagingIntegrationEvents.conversations_archived(nil, valid_payload)
                   end

      assert_raise ArgumentError,
                   ~r/requires a non-empty aggregate_id string/,
                   fn ->
                     MessagingIntegrationEvents.conversations_archived("", valid_payload)
                   end
    end
  end

  describe "participant_added/3" do
    test "creates event with correct type, source_context, and entity_type" do
      conversation_id = Ecto.UUID.generate()

      event =
        MessagingIntegrationEvents.participant_added(conversation_id, %{
          participant_user_ids: [Ecto.UUID.generate()],
          source: :initial_staff
        })

      assert event.event_type == :participant_added
      assert event.source_context == :messaging
      assert event.entity_type == :conversation
      assert event.entity_id == conversation_id
    end

    test "base_payload conversation_id wins over caller-supplied" do
      real_id = Ecto.UUID.generate()
      staff_id = Ecto.UUID.generate()

      event =
        MessagingIntegrationEvents.participant_added(real_id, %{
          conversation_id: "should-be-overridden",
          participant_user_ids: [staff_id],
          source: :later_assignment,
          extra: "data"
        })

      assert event.payload.conversation_id == real_id
      assert event.payload.participant_user_ids == [staff_id]
      assert event.payload.source == "later_assignment"
      assert event.payload.extra == "data"
    end

    test "marks event as critical by default" do
      conversation_id = Ecto.UUID.generate()

      event =
        MessagingIntegrationEvents.participant_added(conversation_id, %{
          participant_user_ids: [Ecto.UUID.generate()],
          source: :initial_staff
        })

      assert IntegrationEvent.critical?(event)
    end

    test "raises when required payload keys are missing" do
      conversation_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/participant_added missing required payload keys/,
                   fn -> MessagingIntegrationEvents.participant_added(conversation_id, %{}) end

      assert_raise ArgumentError,
                   ~r/participant_added missing required payload keys/,
                   fn ->
                     MessagingIntegrationEvents.participant_added(conversation_id, %{
                       participant_user_ids: ["u1"]
                     })
                   end

      assert_raise ArgumentError,
                   ~r/participant_added missing required payload keys/,
                   fn ->
                     MessagingIntegrationEvents.participant_added(conversation_id, %{
                       source: :initial_staff
                     })
                   end
    end

    test "raises when participant_user_ids is empty" do
      conversation_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/participant_added requires a non-empty participant_user_ids list/,
                   fn ->
                     MessagingIntegrationEvents.participant_added(conversation_id, %{
                       participant_user_ids: [],
                       source: :initial_staff
                     })
                   end
    end

    test "raises for nil or empty conversation_id" do
      valid_payload = %{participant_user_ids: ["u1"], source: :initial_staff}

      assert_raise ArgumentError,
                   ~r/requires a non-empty conversation_id string/,
                   fn -> MessagingIntegrationEvents.participant_added(nil, valid_payload) end

      assert_raise ArgumentError,
                   ~r/requires a non-empty conversation_id string/,
                   fn -> MessagingIntegrationEvents.participant_added("", valid_payload) end
    end
  end

  describe "participant_removed/3" do
    test "creates event with correct type, source_context, and entity_type" do
      conversation_id = Ecto.UUID.generate()

      event =
        MessagingIntegrationEvents.participant_removed(conversation_id, %{
          participant_user_ids: [Ecto.UUID.generate()],
          source: :staff_unassignment
        })

      assert event.event_type == :participant_removed
      assert event.source_context == :messaging
      assert event.entity_type == :conversation
      assert event.entity_id == conversation_id
    end

    test "base_payload conversation_id wins over caller-supplied" do
      real_id = Ecto.UUID.generate()
      staff_id = Ecto.UUID.generate()

      event =
        MessagingIntegrationEvents.participant_removed(real_id, %{
          conversation_id: "should-be-overridden",
          participant_user_ids: [staff_id],
          source: :staff_unassignment,
          extra: "data"
        })

      assert event.payload.conversation_id == real_id
      assert event.payload.participant_user_ids == [staff_id]
      assert event.payload.source == "staff_unassignment"
      assert event.payload.extra == "data"
    end

    test "marks event as critical by default" do
      conversation_id = Ecto.UUID.generate()

      event =
        MessagingIntegrationEvents.participant_removed(conversation_id, %{
          participant_user_ids: [Ecto.UUID.generate()],
          source: :staff_unassignment
        })

      assert IntegrationEvent.critical?(event)
    end

    test "raises when required payload keys are missing" do
      conversation_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/participant_removed missing required payload keys/,
                   fn -> MessagingIntegrationEvents.participant_removed(conversation_id, %{}) end

      assert_raise ArgumentError,
                   ~r/participant_removed missing required payload keys/,
                   fn ->
                     MessagingIntegrationEvents.participant_removed(conversation_id, %{
                       participant_user_ids: ["u1"]
                     })
                   end

      assert_raise ArgumentError,
                   ~r/participant_removed missing required payload keys/,
                   fn ->
                     MessagingIntegrationEvents.participant_removed(conversation_id, %{
                       source: :staff_unassignment
                     })
                   end
    end

    test "raises when participant_user_ids is empty" do
      conversation_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/participant_removed requires a non-empty participant_user_ids list/,
                   fn ->
                     MessagingIntegrationEvents.participant_removed(conversation_id, %{
                       participant_user_ids: [],
                       source: :staff_unassignment
                     })
                   end
    end

    test "raises for nil or empty conversation_id" do
      valid_payload = %{participant_user_ids: ["u1"], source: :staff_unassignment}

      assert_raise ArgumentError,
                   ~r/requires a non-empty conversation_id string/,
                   fn -> MessagingIntegrationEvents.participant_removed(nil, valid_payload) end

      assert_raise ArgumentError,
                   ~r/requires a non-empty conversation_id string/,
                   fn -> MessagingIntegrationEvents.participant_removed("", valid_payload) end
    end
  end
end
