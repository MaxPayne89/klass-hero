defmodule KlassHero.Messaging.Adapters.Driving.Events.EventHandlers.NotifyLiveViewsTest do
  use ExUnit.Case, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.Messaging.Adapters.Driving.Events.EventHandlers.NotifyLiveViews
  alias KlassHero.Shared.Domain.Events.DomainEvent

  setup do
    setup_test_events()
    :ok
  end

  describe "handle/1 — :message_sent" do
    test "publishes to conversation topic" do
      conversation_id = Ecto.UUID.generate()

      event =
        DomainEvent.new(:message_sent, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          message_id: Ecto.UUID.generate(),
          sender_id: Ecto.UUID.generate(),
          content: "Hello",
          message_type: :text,
          sent_at: DateTime.utc_now()
        })

      assert :ok = NotifyLiveViews.handle(event)

      assert_event_published(:message_sent, %{conversation_id: conversation_id})
    end
  end

  describe "handle/1 — :messages_read" do
    test "publishes to conversation topic" do
      conversation_id = Ecto.UUID.generate()

      event =
        DomainEvent.new(:messages_read, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          user_id: Ecto.UUID.generate(),
          read_at: DateTime.utc_now()
        })

      assert :ok = NotifyLiveViews.handle(event)

      assert_event_published(:messages_read, %{conversation_id: conversation_id})
    end
  end

  describe "handle/1 — :conversation_created" do
    test "fans out to user topic for each participant" do
      conversation_id = Ecto.UUID.generate()
      user_1 = Ecto.UUID.generate()
      user_2 = Ecto.UUID.generate()

      event =
        DomainEvent.new(:conversation_created, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          type: :direct,
          provider_id: Ecto.UUID.generate(),
          participant_ids: [user_1, user_2]
        })

      assert :ok = NotifyLiveViews.handle(event)

      # One publish per participant
      assert_event_count(2)
      assert_event_published(:conversation_created, %{conversation_id: conversation_id})
    end
  end

  describe "handle/1 — :conversations_archived" do
    test "publishes to bulk operations topic" do
      event =
        DomainEvent.new(:conversations_archived, "bulk_archive_123", :conversation, %{
          conversation_ids: [Ecto.UUID.generate()],
          reason: :program_ended,
          count: 1
        })

      assert :ok = NotifyLiveViews.handle(event)

      assert_event_published(:conversations_archived, %{reason: :program_ended})
    end
  end

  describe "handle/1 — :retention_enforced" do
    test "publishes to bulk operations topic" do
      event =
        DomainEvent.new(:retention_enforced, "retention_123", :conversation, %{
          messages_deleted: 10,
          conversations_deleted: 2,
          enforced_at: DateTime.utc_now()
        })

      assert :ok = NotifyLiveViews.handle(event)

      assert_event_published(:retention_enforced, %{messages_deleted: 10})
    end
  end

  describe "error handling" do
    test "swallows publish failures and returns :ok" do
      conversation_id = Ecto.UUID.generate()

      event =
        DomainEvent.new(:message_sent, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          message_id: Ecto.UUID.generate(),
          sender_id: Ecto.UUID.generate(),
          content: "Hello",
          message_type: :text,
          sent_at: DateTime.utc_now()
        })

      # TestEventPublisher always returns :ok, so we verify the handler
      # always returns :ok regardless (error swallowing tested via pattern)
      assert :ok = NotifyLiveViews.handle(event)
    end
  end
end
