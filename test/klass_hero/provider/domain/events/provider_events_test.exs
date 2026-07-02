defmodule KlassHero.Provider.Domain.Events.ProviderEventsTest do
  use ExUnit.Case, async: true

  alias KlassHero.Provider.Domain.Events.ProviderEvents
  alias KlassHero.Provider.Domain.Models.ProviderProfile
  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Shared.Domain.Events.DomainEvent

  describe "incident_reported/3" do
    test "returns a DomainEvent with the documented payload shape" do
      report = %IncidentReport{
        id: "r1",
        provider_profile_id: "prov-1",
        reporter_user_id: "user-uuid",
        reporter_display_name: "Jane Doe",
        program_id: "prog-1",
        session_id: nil,
        category: :injury,
        severity: :high,
        description: "Scraped knee while running",
        occurred_at: ~U[2026-04-20 10:00:00Z],
        photo_url: "reports/prov-1/photo.jpg",
        original_filename: "photo.jpg"
      }

      profile = %ProviderProfile{
        id: "prov-1",
        identity_id: "owner-uuid",
        business_name: "Acme Adventures",
        business_owner_email: "owner@example.com"
      }

      event = ProviderEvents.incident_reported(report, profile)

      assert %DomainEvent{
               event_type: :incident_reported,
               aggregate_id: "r1",
               aggregate_type: :provider,
               payload: payload
             } = event

      assert payload == %{
               incident_report_id: "r1",
               provider_id: "prov-1",
               program_id: "prog-1",
               session_id: nil,
               reporter_user_id: "user-uuid",
               category: :injury,
               severity: :high,
               occurred_at: ~U[2026-04-20 10:00:00Z],
               has_photo: true,
               business_owner_email: "owner@example.com",
               business_name: "Acme Adventures"
             }

      refute Map.has_key?(payload, :description)
      refute Map.has_key?(payload, :photo_url)
    end

    test "has_photo is false when photo_url is nil" do
      report = %IncidentReport{
        id: "r2",
        provider_profile_id: "prov-1",
        reporter_user_id: "user-uuid",
        reporter_display_name: "Jane Doe",
        program_id: "prog-1",
        session_id: nil,
        category: :other,
        severity: :low,
        description: "Nothing special",
        occurred_at: ~U[2026-04-20 10:00:00Z],
        photo_url: nil,
        original_filename: nil
      }

      profile = %ProviderProfile{
        id: "prov-1",
        identity_id: "owner-uuid",
        business_name: "Acme Adventures",
        business_owner_email: "owner@example.com"
      }

      assert %DomainEvent{payload: %{has_photo: false}} =
               ProviderEvents.incident_reported(report, profile)
    end

    test "forwards opts to DomainEvent.new/5 (e.g., correlation_id)" do
      report = %IncidentReport{
        id: "r3",
        provider_profile_id: "prov-1",
        reporter_user_id: "user-uuid",
        reporter_display_name: "Jane Doe",
        program_id: "prog-1",
        session_id: nil,
        category: :other,
        severity: :low,
        description: "Just checking opts forwarding.",
        occurred_at: ~U[2026-04-20 10:00:00Z],
        photo_url: nil,
        original_filename: nil
      }

      profile = %ProviderProfile{
        id: "prov-1",
        identity_id: "owner-uuid",
        business_name: "Acme Adventures",
        business_owner_email: "owner@example.com"
      }

      correlation_id = Ecto.UUID.generate()

      event =
        ProviderEvents.incident_reported(report, profile, correlation_id: correlation_id)

      assert event.metadata.correlation_id == correlation_id
    end
  end
end
