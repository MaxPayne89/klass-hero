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

  describe "handle/1 — :user_data_anonymized" do
    test "promotes to message_data_anonymized integration event" do
      user_id = Ecto.UUID.generate()
      domain_event = DomainEvent.new(:user_data_anonymized, user_id, :user, %{user_id: user_id})

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:message_data_anonymized)
      assert event.entity_id == user_id
      assert event.source_context == :messaging
      assert IntegrationEvent.critical?(event)
    end

    test "swallows publish failures with :ok" do
      user_id = Ecto.UUID.generate()
      domain_event = DomainEvent.new(:user_data_anonymized, user_id, :user, %{user_id: user_id})

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert :ok = PromoteIntegrationEvents.handle(domain_event)
      assert_no_integration_events_published()
    end
  end

  describe "handle/1 — :conversation_created" do
    test "promotes to conversation_created integration event" do
      conversation_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:conversation_created, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          type: :direct,
          provider_id: Ecto.UUID.generate(),
          participant_ids: [Ecto.UUID.generate(), Ecto.UUID.generate()]
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:conversation_created)
      assert event.entity_id == conversation_id
      assert event.source_context == :messaging
      assert event.entity_type == :conversation
    end

    test "propagates publish failures as {:error, reason}" do
      conversation_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:conversation_created, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          type: :direct,
          provider_id: Ecto.UUID.generate(),
          participant_ids: [Ecto.UUID.generate(), Ecto.UUID.generate()]
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert {:error, :pubsub_down} = PromoteIntegrationEvents.handle(domain_event)
    end
  end

  describe "handle/1 — :message_sent" do
    test "promotes to message_sent integration event" do
      conversation_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:message_sent, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          message_id: Ecto.UUID.generate(),
          sender_id: Ecto.UUID.generate(),
          content: "Hello!",
          message_type: :text,
          sent_at: DateTime.utc_now()
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:message_sent)
      assert event.entity_id == conversation_id
      assert event.source_context == :messaging
      assert event.payload.content == "Hello!"
    end

    test "propagates publish failures as {:error, reason}" do
      conversation_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:message_sent, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          message_id: Ecto.UUID.generate(),
          sender_id: Ecto.UUID.generate(),
          content: "Hello!",
          message_type: :text,
          sent_at: DateTime.utc_now()
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert {:error, :pubsub_down} = PromoteIntegrationEvents.handle(domain_event)
    end
  end

  describe "handle/1 — :messages_read" do
    test "promotes to messages_read integration event" do
      conversation_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:messages_read, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          user_id: user_id,
          read_at: DateTime.utc_now()
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:messages_read)
      assert event.entity_id == conversation_id
      assert event.source_context == :messaging
      assert event.payload.user_id == user_id
    end

    test "swallows publish failures with :ok" do
      conversation_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:messages_read, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          user_id: Ecto.UUID.generate(),
          read_at: DateTime.utc_now()
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert :ok = PromoteIntegrationEvents.handle(domain_event)
      assert_no_integration_events_published()
    end
  end

  describe "handle/1 — :conversation_archived" do
    test "promotes to conversation_archived integration event" do
      conversation_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:conversation_archived, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          reason: :program_ended
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:conversation_archived)
      assert event.entity_id == conversation_id
      assert event.source_context == :messaging
    end

    test "swallows publish failures with :ok" do
      conversation_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:conversation_archived, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          reason: :program_ended
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert :ok = PromoteIntegrationEvents.handle(domain_event)
      assert_no_integration_events_published()
    end
  end

  describe "handle/1 — :conversations_archived" do
    test "promotes to conversations_archived integration event" do
      aggregate_id = "bulk_archive_123"

      domain_event =
        DomainEvent.new(:conversations_archived, aggregate_id, :conversation, %{
          conversation_ids: [Ecto.UUID.generate(), Ecto.UUID.generate()],
          reason: :program_ended,
          count: 2
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:conversations_archived)
      assert event.entity_id == aggregate_id
      assert event.source_context == :messaging
      assert event.payload.count == 2
    end

    test "swallows publish failures with :ok" do
      aggregate_id = "bulk_archive_123"

      domain_event =
        DomainEvent.new(:conversations_archived, aggregate_id, :conversation, %{
          conversation_ids: [Ecto.UUID.generate(), Ecto.UUID.generate()],
          reason: :program_ended,
          count: 2
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert :ok = PromoteIntegrationEvents.handle(domain_event)
      assert_no_integration_events_published()
    end
  end

  describe "handle/1 — :participant_added" do
    test "promotes to participant_added integration event" do
      conversation_id = Ecto.UUID.generate()
      user_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      domain_event =
        DomainEvent.new(:participant_added, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          participant_user_ids: user_ids,
          source: :initial_staff
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:participant_added)
      assert event.entity_id == conversation_id
      assert event.source_context == :messaging
      assert event.entity_type == :conversation
      assert event.payload.participant_user_ids == user_ids
      assert event.payload.source == "initial_staff"
      assert IntegrationEvent.critical?(event)
    end

    test "propagates publish failures as {:error, reason}" do
      conversation_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:participant_added, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          participant_user_ids: [Ecto.UUID.generate()],
          source: :later_assignment
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert {:error, :pubsub_down} = PromoteIntegrationEvents.handle(domain_event)
    end
  end

  describe "handle/1 — :participant_removed" do
    test "promotes to participant_removed integration event" do
      conversation_id = Ecto.UUID.generate()
      user_ids = [Ecto.UUID.generate()]

      domain_event =
        DomainEvent.new(:participant_removed, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          participant_user_ids: user_ids,
          source: :staff_unassignment
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:participant_removed)
      assert event.entity_id == conversation_id
      assert event.source_context == :messaging
      assert event.entity_type == :conversation
      assert event.payload.participant_user_ids == user_ids
      assert event.payload.source == "staff_unassignment"
      assert IntegrationEvent.critical?(event)
    end

    test "propagates publish failures as {:error, reason}" do
      conversation_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:participant_removed, conversation_id, :conversation, %{
          conversation_id: conversation_id,
          participant_user_ids: [Ecto.UUID.generate()],
          source: :staff_unassignment
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert {:error, :pubsub_down} = PromoteIntegrationEvents.handle(domain_event)
    end
  end
end
