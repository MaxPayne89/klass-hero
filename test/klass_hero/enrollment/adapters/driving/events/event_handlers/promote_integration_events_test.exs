defmodule KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEventsTest do
  use ExUnit.Case, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents
  alias KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher
  alias KlassHero.Shared.Domain.Events.DomainEvent

  setup do
    setup_test_integration_events()
    :ok
  end

  # Each enrollment domain event promotes to an integration event with a known
  # entity_type, and publish failures propagate as {:error, reason}. The table
  # drives that shared contract; per-event payload passthrough is kept below.
  @cases [
    %{type: :participant_policy_set, entity_type: :participant_policy, payload: %{program_id: "id-1"}},
    %{
      type: :enrollment_cancelled,
      entity_type: :enrollment,
      payload: %{enrollment_id: "id-1", admin_id: "admin-1", reason: "Duplicate booking"}
    },
    %{
      type: :invite_claimed,
      entity_type: :invite,
      payload: %{
        invite_id: "id-1",
        user_id: "user-1",
        program_id: "prog-1",
        is_new_user: true,
        child: %{first_name: "Emma", last_name: "Schmidt"},
        guardian: %{email: "parent@example.com"}
      }
    }
  ]

  for %{type: type, entity_type: entity_type, payload: payload} <- @cases do
    describe "handle/1 — #{type}" do
      @type_ type
      @entity_type entity_type
      @payload payload

      test "promotes to the #{type} integration event" do
        domain_event = DomainEvent.new(@type_, "id-1", :enrollment, @payload)

        assert :ok = PromoteIntegrationEvents.handle(domain_event)

        event = assert_integration_event_published(@type_)
        assert event.entity_id == "id-1"
        assert event.source_context == :enrollment
        assert event.entity_type == @entity_type
      end

      test "propagates publish failures as {:error, reason}" do
        domain_event = DomainEvent.new(@type_, "id-1", :enrollment, @payload)
        TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

        assert {:error, :pubsub_down} = PromoteIntegrationEvents.handle(domain_event)
      end
    end
  end

  describe "handle/1 — payload passthrough" do
    test "enrollment_cancelled carries enrollment_id and admin_id" do
      payload = %{enrollment_id: "id-1", admin_id: "admin-1", reason: "Duplicate booking"}

      assert :ok = PromoteIntegrationEvents.handle(DomainEvent.new(:enrollment_cancelled, "id-1", :enrollment, payload))

      event = assert_integration_event_published(:enrollment_cancelled)
      assert event.payload.enrollment_id == "id-1"
      assert event.payload.admin_id == "admin-1"
    end

    test "invite_claimed carries invite_id and user_id" do
      payload = %{invite_id: "id-1", user_id: "user-1", program_id: "prog-1"}

      assert :ok = PromoteIntegrationEvents.handle(DomainEvent.new(:invite_claimed, "id-1", :enrollment, payload))

      event = assert_integration_event_published(:invite_claimed)
      assert event.payload.invite_id == "id-1"
      assert event.payload.user_id == "user-1"
    end
  end
end
