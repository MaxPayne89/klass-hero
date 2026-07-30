defmodule KlassHero.Enrollment.Domain.Events.EnrollmentEventsInviteClaimedTest do
  use ExUnit.Case, async: true

  alias KlassHero.Enrollment.Domain.Events.EnrollmentEvents
  alias KlassHero.Shared.Domain.Events.Event

  describe "invite_claimed/3" do
    test "creates a domain event with correct structure" do
      invite_id = Ecto.UUID.generate()

      payload = %{
        invite_id: invite_id,
        user_id: Ecto.UUID.generate(),
        program_id: Ecto.UUID.generate(),
        provider_id: Ecto.UUID.generate(),
        is_new_user: true,
        child: %{first_name: "Emma", last_name: "Schmidt"},
        guardian: %{email: "parent@example.com"},
        consents: %{photo_marketing: false}
      }

      event = EnrollmentEvents.invite_claimed(invite_id, payload)

      assert %Event{} = event
      assert event.event_type == :invite_claimed
      assert event.entity_id == invite_id
      assert event.entity_type == :invite
      assert event.payload.invite_id == invite_id
    end

    test "raises on empty invite_id" do
      assert_raise ArgumentError, fn ->
        EnrollmentEvents.invite_claimed("", %{})
      end
    end
  end
end
