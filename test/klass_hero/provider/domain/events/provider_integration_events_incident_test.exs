defmodule KlassHero.Provider.Domain.Events.ProviderIntegrationEventsIncidentTest do
  @moduledoc """
  Tests for incident-related factory functions in ProviderIntegrationEvents.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.Domain.Events.ProviderIntegrationEvents
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  describe "incident_reported/3" do
    setup do
      %{
        incident_report_id: Ecto.UUID.generate(),
        provider_id: Ecto.UUID.generate()
      }
    end

    test "creates event with correct type, source_context, and entity_type", %{
      incident_report_id: incident_report_id
    } do
      event = ProviderIntegrationEvents.incident_reported(incident_report_id)

      assert %IntegrationEvent{} = event
      assert event.event_type == :incident_reported
      assert event.source_context == :provider
      assert event.entity_type == :incident_report
      assert event.entity_id == incident_report_id
    end

    test "includes incident_report_id in payload and passes through extra fields", %{
      incident_report_id: incident_report_id,
      provider_id: provider_id
    } do
      event =
        ProviderIntegrationEvents.incident_reported(incident_report_id, %{
          provider_id: provider_id,
          category: :injury,
          severity: :high
        })

      assert event.payload.incident_report_id == incident_report_id
      assert event.payload.provider_id == provider_id
      assert event.payload.category == "injury"
      assert event.payload.severity == "high"
    end

    test "base_payload incident_report_id wins over caller-supplied incident_report_id", %{
      incident_report_id: real_id
    } do
      conflicting_payload = %{incident_report_id: "should-be-overridden", extra: "data"}

      event = ProviderIntegrationEvents.incident_reported(real_id, conflicting_payload)

      assert event.payload.incident_report_id == real_id
      assert event.payload.extra == "data"
    end

    test "marks event as critical by default", %{incident_report_id: incident_report_id} do
      event = ProviderIntegrationEvents.incident_reported(incident_report_id)

      assert IntegrationEvent.critical?(event)
    end

    test "allows overriding criticality via opts", %{incident_report_id: incident_report_id} do
      event =
        ProviderIntegrationEvents.incident_reported(incident_report_id, %{}, criticality: :normal)

      refute IntegrationEvent.critical?(event)
    end

    test "raises for nil incident_report_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty incident_report_id string/,
                   fn -> ProviderIntegrationEvents.incident_reported(nil) end
    end

    test "raises for empty string incident_report_id" do
      assert_raise ArgumentError,
                   ~r/requires a non-empty incident_report_id string/,
                   fn -> ProviderIntegrationEvents.incident_reported("") end
    end
  end
end
