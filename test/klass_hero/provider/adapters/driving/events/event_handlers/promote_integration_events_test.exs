defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEventsTest do
  use ExUnit.Case, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  setup do
    setup_test_integration_events()
    :ok
  end

  # staff_assigned/unassigned are a mirror pair: same consumer-read fields and
  # criticality, differing only in the timestamp key that must NOT cross the
  # boundary (#1004). The table drives both; trim_key names the dropped field.
  @staff_cases [
    %{type: :staff_assigned_to_program, trim_key: :assigned_at},
    %{type: :staff_unassigned_from_program, trim_key: :unassigned_at}
  ]

  for %{type: type, trim_key: trim_key} <- @staff_cases do
    describe "handle/1 — #{type}" do
      @type_ type
      @trim_key trim_key

      test "promotes to a critical integration event carrying the consumer-read fields" do
        staff_member_id = Ecto.UUID.generate()
        provider_id = Ecto.UUID.generate()
        program_id = Ecto.UUID.generate()
        staff_user_id = Ecto.UUID.generate()

        domain_event =
          DomainEvent.new(@type_, Ecto.UUID.generate(), :provider, %{
            @trim_key => ~U[2026-07-04 10:00:00Z],
            provider_id: provider_id,
            program_id: program_id,
            staff_member_id: staff_member_id,
            staff_user_id: staff_user_id
          })

        assert :ok = PromoteIntegrationEvents.handle(domain_event)

        event = assert_integration_event_published(@type_)
        assert event.source_context == :provider
        assert event.entity_type == :staff_member
        assert IntegrationEvent.critical?(event)
        assert event.payload.staff_member_id == staff_member_id
        assert event.payload.provider_id == provider_id
        assert event.payload.program_id == program_id
        assert event.payload.staff_user_id == staff_user_id
      end

      test "trims the #{trim_key} DateTime from the integration payload" do
        # #1004: durable Oban delivery serializes the payload to jsonb; a DateTime
        # would deserialize back to a string. No consumer reads this timestamp, so
        # it must not cross the boundary.
        domain_event =
          DomainEvent.new(@type_, Ecto.UUID.generate(), :provider, %{
            @trim_key => ~U[2026-07-04 10:00:00Z],
            provider_id: Ecto.UUID.generate(),
            program_id: Ecto.UUID.generate(),
            staff_member_id: Ecto.UUID.generate(),
            staff_user_id: Ecto.UUID.generate()
          })

        assert :ok = PromoteIntegrationEvents.handle(domain_event)

        event = assert_integration_event_published(@type_)
        refute Map.has_key?(event.payload, @trim_key)
      end
    end
  end
end
