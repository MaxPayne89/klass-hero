defmodule KlassHero.Messaging.Domain.Events.MessagingEventsTest do
  @moduledoc """
  Tests for MessagingEvents domain event factory module.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Messaging.Domain.Events.MessagingEvents

  describe "conversation_created/4" do
    test "creates event with correct type and payload" do
      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()
      participant_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      event =
        MessagingEvents.conversation_created(
          conversation_id,
          :direct,
          provider_id,
          participant_ids
        )

      assert event.event_type == :conversation_created
      assert event.aggregate_id == conversation_id
      assert event.aggregate_type == :conversation
      assert event.payload.conversation_id == conversation_id
      assert event.payload.type == :direct
      assert event.payload.provider_id == provider_id
      assert event.payload.participant_ids == participant_ids
    end
  end

  describe "message_sent/6" do
    test "creates event with correct type and payload" do
      conversation_id = Ecto.UUID.generate()
      message_id = Ecto.UUID.generate()
      sender_id = Ecto.UUID.generate()
      sent_at = DateTime.utc_now()

      event =
        MessagingEvents.message_sent(
          conversation_id,
          message_id,
          sender_id,
          "Hello!",
          :text,
          sent_at
        )

      assert event.event_type == :message_sent
      assert event.aggregate_id == conversation_id
      assert event.aggregate_type == :conversation
      assert event.payload.message_id == message_id
      assert event.payload.sender_id == sender_id
      assert event.payload.content == "Hello!"
      assert event.payload.message_type == :text
      assert event.payload.sent_at == sent_at
    end

    test "defaults sent_at when not provided" do
      event =
        MessagingEvents.message_sent(
          Ecto.UUID.generate(),
          Ecto.UUID.generate(),
          Ecto.UUID.generate(),
          "Hello!",
          :text
        )

      assert %DateTime{} = event.payload.sent_at
    end
  end

  describe "messages_read/3" do
    test "creates event with correct type and payload" do
      conversation_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()
      read_at = DateTime.utc_now()

      event = MessagingEvents.messages_read(conversation_id, user_id, read_at)

      assert event.event_type == :messages_read
      assert event.aggregate_id == conversation_id
      assert event.aggregate_type == :conversation
      assert event.payload.user_id == user_id
      assert event.payload.read_at == read_at
    end
  end

  describe "conversation_archived/2" do
    test "creates event with correct type and payload" do
      conversation_id = Ecto.UUID.generate()

      event = MessagingEvents.conversation_archived(conversation_id, :program_ended)

      assert event.event_type == :conversation_archived
      assert event.aggregate_id == conversation_id
      assert event.aggregate_type == :conversation
      assert event.payload.reason == :program_ended
    end
  end

  describe "conversations_archived/3" do
    test "creates event with correct type and payload" do
      ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      event = MessagingEvents.conversations_archived(ids, :retention_policy, 2)

      assert event.event_type == :conversations_archived
      assert event.aggregate_type == :conversation
      assert event.payload.conversation_ids == ids
      assert event.payload.reason == :retention_policy
      assert event.payload.count == 2
    end
  end

  describe "retention_enforced/2" do
    test "creates event with correct type and payload" do
      event = MessagingEvents.retention_enforced(10, 3)

      assert event.event_type == :retention_enforced
      assert event.aggregate_type == :conversation
      assert event.payload.messages_deleted == 10
      assert event.payload.conversations_deleted == 3
      assert %DateTime{} = event.payload.enforced_at
    end
  end

  describe "user_data_anonymized/1" do
    test "creates event with correct type and payload" do
      user_id = Ecto.UUID.generate()
      event = MessagingEvents.user_data_anonymized(user_id)

      assert event.event_type == :user_data_anonymized
      assert event.aggregate_id == user_id
      assert event.aggregate_type == :user
      assert event.payload.user_id == user_id
    end
  end
end
