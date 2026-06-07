defmodule KlassHero.Accounts.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEventsTest do
  use ExUnit.Case, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.Accounts.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents
  alias KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  setup do
    setup_test_integration_events()
    :ok
  end

  describe "handle/1 — :user_registered" do
    test "promotes to user_registered integration event" do
      user_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:user_registered, user_id, :user, %{
          email: "test@example.com",
          name: "Test User",
          intended_roles: ["parent"]
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:user_registered)
      assert event.entity_id == user_id
      assert event.source_context == :accounts
      assert event.payload.user_id == user_id
      assert IntegrationEvent.critical?(event)
    end

    test "propagates publish failures" do
      user_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:user_registered, user_id, :user, %{
          email: "test@example.com",
          name: "Test User",
          intended_roles: ["parent"]
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert {:error, :pubsub_down} = PromoteIntegrationEvents.handle(domain_event)
    end
  end

  describe "handle/1 — :user_anonymized" do
    test "promotes to user_anonymized integration event" do
      user_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:user_anonymized, user_id, :user, %{
          anonymized_email: "deleted_#{user_id}@anonymized.local",
          previous_email: "old@example.com",
          anonymized_at: DateTime.utc_now()
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:user_anonymized)
      assert event.entity_id == user_id
      assert event.source_context == :accounts
      assert event.payload.user_id == user_id
      assert IntegrationEvent.critical?(event)
    end

    test "propagates publish failures" do
      user_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:user_anonymized, user_id, :user, %{
          anonymized_email: "deleted_#{user_id}@anonymized.local",
          previous_email: "old@example.com",
          anonymized_at: DateTime.utc_now()
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert {:error, :pubsub_down} = PromoteIntegrationEvents.handle(domain_event)
    end
  end

  describe "handle/1 — :user_confirmed" do
    test "promotes to user_confirmed integration event" do
      user_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:user_confirmed, user_id, :user, %{
          email: "test@example.com",
          name: "Test Provider",
          confirmed_at: ~U[2024-01-01 12:00:00Z],
          intended_roles: ["provider"]
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:user_confirmed)
      assert event.entity_id == user_id
      assert event.source_context == :accounts
      assert event.payload.user_id == user_id
      assert event.payload.intended_roles == ["provider"]
      assert IntegrationEvent.critical?(event)
    end

    test "propagates publish failures" do
      user_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:user_confirmed, user_id, :user, %{
          email: "test@example.com",
          name: "Test User",
          confirmed_at: ~U[2024-01-01 12:00:00Z],
          intended_roles: ["parent"]
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert {:error, :pubsub_down} = PromoteIntegrationEvents.handle(domain_event)
    end
  end
end
