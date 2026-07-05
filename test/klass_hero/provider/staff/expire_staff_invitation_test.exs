defmodule KlassHero.Provider.Staff.ExpireStaffInvitationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.ProviderFixtures

  alias KlassHero.Provider
  alias KlassHero.Provider.StaffMember

  # Only :sent invitations may transition to :expired; every other status is an
  # invalid transition.
  @invalid_source_statuses [:pending, :accepted, :failed, :expired]

  defp staff_with_status(status) do
    provider = provider_profile_fixture()
    attrs = %{provider_id: provider.id, invitation_status: status}

    # A token hash is only valid on statuses that carry a live/used token; the
    # invitation changeset rejects it on :pending/:accepted (which need a user_id).
    # The hash is unique per call — several staff are created in one transaction
    # within a single tabular test, and the column has a unique index.
    attrs =
      if status in [:sent, :failed, :expired],
        do: Map.put(attrs, :invitation_token_hash, :crypto.hash(:sha256, "tok-#{System.unique_integer([:positive])}")),
        else: attrs

    staff_member_fixture(attrs)
  end

  describe "execute/1 with staff_member_id" do
    test "transitions a :sent invitation to :expired" do
      staff = staff_with_status(:sent)

      assert {:ok, %StaffMember{} = updated} = Provider.expire_staff_invitation(staff.id)
      assert updated.id == staff.id
      assert updated.invitation_status == :expired
    end

    test "rejects expiry from any non-:sent status" do
      for status <- @invalid_source_statuses do
        staff = staff_with_status(status)

        assert {:error, :invalid_invitation_transition} = Provider.expire_staff_invitation(staff.id),
               "expected #{status} → :expired to be rejected"
      end
    end

    test "returns :not_found for a non-existent staff member" do
      assert {:error, :not_found} = Provider.expire_staff_invitation(Ecto.UUID.generate())
    end
  end

  describe "execute/1 with %StaffMember{} struct" do
    test "transitions a :sent invitation to :expired without re-fetching from DB" do
      staff = staff_with_status(:sent)

      assert {:ok, %StaffMember{} = updated} = Provider.expire_staff_invitation(staff)
      assert updated.id == staff.id
      assert updated.invitation_status == :expired
    end

    test "rejects expiry from any non-:sent status" do
      for status <- @invalid_source_statuses do
        staff = staff_with_status(status)

        assert {:error, :invalid_invitation_transition} = Provider.expire_staff_invitation(staff),
               "expected #{status} → :expired to be rejected"
      end
    end
  end
end
