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

  # Each accounts domain event promotes to a critical integration event carrying
  # user_id, and publish failures propagate as {:error, reason}. The table drives
  # that shared contract; user_confirmed's intended_roles passthrough is the one
  # factory-specific assertion, kept below the table.
  @cases [
    %{type: :user_registered, payload: %{email: "test@example.com", name: "Test User", intended_roles: ["parent"]}},
    %{
      type: :user_anonymized,
      payload: %{
        anonymized_email: "deleted@anonymized.local",
        previous_email: "old@example.com",
        anonymized_at: "2024-01-01T12:00:00Z"
      }
    },
    %{
      type: :user_confirmed,
      payload: %{
        email: "test@example.com",
        name: "Test User",
        confirmed_at: "2024-01-01T12:00:00Z",
        intended_roles: ["provider"]
      }
    }
  ]

  for %{type: type, payload: payload} <- @cases do
    describe "handle/1 — #{type}" do
      @type_ type
      @payload payload

      test "promotes to the #{type} critical integration event" do
        domain_event = DomainEvent.new(@type_, "user-1", :user, @payload)

        assert :ok = PromoteIntegrationEvents.handle(domain_event)

        event = assert_integration_event_published(@type_)
        assert event.entity_id == "user-1"
        assert event.source_context == :accounts
        assert event.payload.user_id == "user-1"
        assert IntegrationEvent.critical?(event)
      end

      test "propagates publish failures" do
        domain_event = DomainEvent.new(@type_, "user-1", :user, @payload)
        TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

        assert {:error, :pubsub_down} = PromoteIntegrationEvents.handle(domain_event)
      end
    end
  end

  describe "handle/1 — :user_confirmed payload" do
    test "carries intended_roles through to the integration event" do
      payload = %{
        email: "test@example.com",
        name: "Test Provider",
        confirmed_at: "2024-01-01T12:00:00Z",
        intended_roles: ["provider"]
      }

      assert :ok = PromoteIntegrationEvents.handle(DomainEvent.new(:user_confirmed, "user-1", :user, payload))

      event = assert_integration_event_published(:user_confirmed)
      assert event.payload.intended_roles == ["provider"]
    end
  end
end
