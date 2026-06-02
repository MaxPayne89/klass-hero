defmodule KlassHero.Provider.Application.Commands.StaffMembers.ExpireStaffInvitationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.ProviderFixtures

  alias KlassHero.Provider.Application.Commands.StaffMembers.ExpireStaffInvitation
  alias KlassHero.Provider.Domain.Models.StaffMember

  describe "execute/1 with staff_member_id" do
    test "transitions :sent invitation to :expired" do
      provider = provider_profile_fixture()

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          invitation_status: :sent,
          invitation_token_hash: :crypto.hash(:sha256, "tok")
        })

      assert {:ok, %StaffMember{} = updated} = ExpireStaffInvitation.execute(staff.id)
      assert updated.id == staff.id
      assert updated.invitation_status == :expired
    end

    test "returns error for :pending staff member (invalid transition)" do
      provider = provider_profile_fixture()

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          invitation_status: :pending
        })

      assert {:error, :invalid_invitation_transition} = ExpireStaffInvitation.execute(staff.id)
    end

    test "returns error for :accepted staff member (invalid transition)" do
      provider = provider_profile_fixture()

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          invitation_status: :accepted
        })

      assert {:error, :invalid_invitation_transition} = ExpireStaffInvitation.execute(staff.id)
    end

    test "returns error for :failed staff member (invalid transition)" do
      provider = provider_profile_fixture()

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          invitation_status: :failed,
          invitation_token_hash: :crypto.hash(:sha256, "tok")
        })

      assert {:error, :invalid_invitation_transition} = ExpireStaffInvitation.execute(staff.id)
    end

    test "returns :not_found for non-existent staff member" do
      assert {:error, :not_found} = ExpireStaffInvitation.execute(Ecto.UUID.generate())
    end
  end

  describe "execute/1 with %StaffMember{} struct" do
    test "transitions :sent invitation to :expired without re-fetching from DB" do
      provider = provider_profile_fixture()

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          invitation_status: :sent,
          invitation_token_hash: :crypto.hash(:sha256, "tok")
        })

      assert {:ok, %StaffMember{} = updated} = ExpireStaffInvitation.execute(staff)
      assert updated.id == staff.id
      assert updated.invitation_status == :expired
    end

    test "returns error for :expired → :expired (no self-transition defined)" do
      provider = provider_profile_fixture()

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          invitation_status: :expired,
          invitation_token_hash: :crypto.hash(:sha256, "tok")
        })

      assert {:error, :invalid_invitation_transition} = ExpireStaffInvitation.execute(staff)
    end
  end
end
