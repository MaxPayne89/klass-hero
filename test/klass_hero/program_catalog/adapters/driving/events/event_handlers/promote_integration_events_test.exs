defmodule KlassHero.ProgramCatalog.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEventsTest do
  use ExUnit.Case, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.ProgramCatalog.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents
  alias KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher
  alias KlassHero.Shared.Domain.Events.DomainEvent

  setup do
    setup_test_integration_events()
    :ok
  end

  # Each program-catalog domain event promotes to a :program integration event,
  # and publish failures propagate as {:error, reason}. The table drives that
  # shared contract; program_updated's title passthrough is kept below.
  @cases [
    %{type: :program_created, payload: %{provider_id: "pv-1", title: "Summer Camp", category: "sports"}},
    %{type: :program_updated, payload: %{provider_id: "pv-1", title: "Updated Title", price: "200.00"}}
  ]

  for %{type: type, payload: payload} <- @cases do
    describe "handle/1 — #{type}" do
      @type_ type
      @payload payload

      test "promotes to the #{type} integration event" do
        domain_event = DomainEvent.new(@type_, "prog-1", :program, @payload)

        assert :ok = PromoteIntegrationEvents.handle(domain_event)

        event = assert_integration_event_published(@type_)
        assert event.entity_id == "prog-1"
        assert event.source_context == :program_catalog
        assert event.entity_type == :program
      end

      test "propagates publish failures as {:error, reason}" do
        domain_event = DomainEvent.new(@type_, "prog-1", :program, @payload)
        TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

        assert {:error, :pubsub_down} = PromoteIntegrationEvents.handle(domain_event)
      end
    end
  end

  describe "handle/1 — :program_updated payload" do
    test "carries the updated title through to the integration event" do
      payload = %{provider_id: "pv-1", title: "Updated Title", price: "200.00"}

      assert :ok = PromoteIntegrationEvents.handle(DomainEvent.new(:program_updated, "prog-1", :program, payload))

      event = assert_integration_event_published(:program_updated)
      assert event.payload.title == "Updated Title"
    end
  end
end
