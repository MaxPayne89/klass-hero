defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEventsTest do
  use ExUnit.Case, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents
  alias KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  setup do
    setup_test_integration_events()
    :ok
  end

  describe "handle/1 — :incident_reported" do
    test "promotes to incident_reported integration event" do
      incident_report_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:incident_reported, incident_report_id, :provider, %{
          incident_report_id: incident_report_id,
          provider_id: provider_id,
          program_id: Ecto.UUID.generate(),
          session_id: nil,
          reporter_user_id: Ecto.UUID.generate(),
          category: :injury,
          severity: :high,
          occurred_at: ~U[2026-04-20 10:00:00Z],
          has_photo: true
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:incident_reported)
      assert event.entity_id == incident_report_id
      assert event.source_context == :provider
      assert event.entity_type == :incident_report
      assert event.payload.incident_report_id == incident_report_id
      assert event.payload.provider_id == provider_id
      assert event.payload.category == :injury
      assert event.payload.severity == :high
      assert event.payload.has_photo == true
    end

    test "publishes the integration event as :critical" do
      incident_report_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:incident_reported, incident_report_id, :provider, %{
          incident_report_id: incident_report_id,
          provider_id: Ecto.UUID.generate(),
          program_id: Ecto.UUID.generate(),
          session_id: nil,
          reporter_user_id: Ecto.UUID.generate(),
          category: :other,
          severity: :low,
          occurred_at: ~U[2026-04-20 10:00:00Z],
          has_photo: false
        })

      assert :ok = PromoteIntegrationEvents.handle(domain_event)

      event = assert_integration_event_published(:incident_reported)
      assert IntegrationEvent.critical?(event)
    end

    test "propagates publish failures as {:error, reason}" do
      incident_report_id = Ecto.UUID.generate()

      domain_event =
        DomainEvent.new(:incident_reported, incident_report_id, :provider, %{
          incident_report_id: incident_report_id,
          provider_id: Ecto.UUID.generate(),
          program_id: Ecto.UUID.generate(),
          session_id: nil,
          reporter_user_id: Ecto.UUID.generate(),
          category: :injury,
          severity: :high,
          occurred_at: ~U[2026-04-20 10:00:00Z],
          has_photo: true
        })

      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert {:error, :pubsub_down} = PromoteIntegrationEvents.handle(domain_event)
    end
  end
end
