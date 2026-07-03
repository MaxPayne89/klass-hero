defmodule KlassHero.Provider.Application.Commands.StaffMembers.ResendStaffInvitationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper
  import KlassHero.ProviderFixtures

  alias KlassHero.Provider
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher

  setup do
    setup_test_integration_events()
    :ok
  end

  describe "execute/1" do
    test "resends invitation for :failed staff member" do
      provider = provider_profile_fixture()
      old_token = :crypto.hash(:sha256, "old-token")

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          email: "staff@example.com",
          invitation_status: :failed,
          invitation_token_hash: old_token
        })

      assert {:ok, updated, raw_token} = Provider.resend_staff_invitation(staff.id)

      assert updated.invitation_status == :pending
      assert updated.invitation_token_hash != old_token
      assert is_binary(raw_token)
    end

    test "resends invitation for :expired staff member" do
      provider = provider_profile_fixture()

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          email: "staff@example.com",
          invitation_status: :expired,
          invitation_token_hash: :crypto.hash(:sha256, "old")
        })

      assert {:ok, updated, _raw_token} = Provider.resend_staff_invitation(staff.id)
      assert updated.invitation_status == :pending
    end

    test "fails for :sent staff member (invalid transition)" do
      provider = provider_profile_fixture()

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          email: "staff@example.com",
          invitation_status: :sent,
          invitation_token_hash: :crypto.hash(:sha256, "tok")
        })

      assert {:error, :invalid_invitation_transition} = Provider.resend_staff_invitation(staff.id)
    end

    test "fails for :accepted staff member" do
      provider = provider_profile_fixture()

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          email: "staff@example.com",
          invitation_status: :accepted
        })

      assert {:error, :invalid_invitation_transition} = Provider.resend_staff_invitation(staff.id)
    end

    test "returns error for non-existent staff member" do
      assert {:error, :not_found} = Provider.resend_staff_invitation(Ecto.UUID.generate())
    end

    test "emits :staff_member_invited integration event on success" do
      provider = provider_profile_fixture()

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          email: "staff@example.com",
          invitation_status: :failed,
          invitation_token_hash: :crypto.hash(:sha256, "old-token")
        })

      {:ok, _updated, _raw_token} = Provider.resend_staff_invitation(staff.id)

      event = assert_integration_event_published(:staff_member_invited)
      assert event.entity_id == staff.id
      assert event.payload.staff_member_id == staff.id
      assert event.payload.provider_id == provider.id
      assert event.payload.email == "staff@example.com"
      assert event.payload.business_name == provider.business_name
      assert is_binary(event.payload.raw_token)
    end

    test "new raw_token hashes to the stored token_hash" do
      provider = provider_profile_fixture()

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          email: "staff@example.com",
          invitation_status: :failed,
          invitation_token_hash: :crypto.hash(:sha256, "old-token")
        })

      {:ok, updated, raw_token} = Provider.resend_staff_invitation(staff.id)

      assert :crypto.hash(:sha256, Base.url_decode64!(raw_token, padding: false)) ==
               updated.invitation_token_hash
    end

    test "compensates to :failed when event publishing fails" do
      provider = provider_profile_fixture()

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          email: "staff@example.com",
          invitation_status: :failed,
          invitation_token_hash: :crypto.hash(:sha256, "old-token")
        })

      # Clear events from fixture setup, then configure publish to fail
      clear_integration_events()
      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      assert {:error, :invitation_emission_failed} = Provider.resend_staff_invitation(staff.id)

      # Verify compensation: staff member in :failed, not orphaned as :pending
      schema = Repo.get!(StaffMember, staff.id)
      assert schema.invitation_status == :failed

      assert_no_integration_events_published()
    end
  end
end
