defmodule KlassHero.Provider.Application.Commands.StaffMembers.AcceptStaffInvitationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.ProviderFixtures

  alias KlassHero.Provider
  alias KlassHero.Provider.Application.Commands.StaffMembers.AcceptStaffInvitation

  defp sent_staff(provider, opts \\ []) do
    staff_member_fixture(
      Keyword.merge(
        [
          provider_id: provider.id,
          email: "invited-#{System.unique_integer([:positive])}@example.com",
          invitation_status: :sent,
          invitation_token_hash: :crypto.hash(:sha256, "tok-#{System.unique_integer([:positive])}"),
          invitation_sent_at: DateTime.utc_now()
        ],
        opts
      )
    )
  end

  describe "execute/2" do
    test "links the user and transitions a sent invitation to accepted" do
      provider = provider_profile_fixture()
      staff = sent_staff(provider)
      user_id = user_fixture().id

      assert {:ok, accepted} = AcceptStaffInvitation.execute(staff, user_id)
      assert accepted.invitation_status == :accepted
      assert accepted.user_id == user_id
    end

    test "is idempotent — re-accepting by the same user is a no-op success" do
      provider = provider_profile_fixture()
      staff = sent_staff(provider)
      user_id = user_fixture().id

      assert {:ok, accepted} = AcceptStaffInvitation.execute(staff, user_id)
      assert {:ok, again} = AcceptStaffInvitation.execute(accepted, user_id)

      assert again.invitation_status == :accepted
      assert again.user_id == user_id
    end

    test "supports multi-employer — same user accepts at two different providers" do
      user_id = user_fixture().id
      staff_a = sent_staff(provider_profile_fixture())
      staff_b = sent_staff(provider_profile_fixture())

      assert {:ok, a} = AcceptStaffInvitation.execute(staff_a, user_id)
      assert {:ok, b} = AcceptStaffInvitation.execute(staff_b, user_id)

      assert a.user_id == user_id
      assert b.user_id == user_id
      assert a.provider_id != b.provider_id
    end

    test "exposed via the Provider facade" do
      provider = provider_profile_fixture()
      staff = sent_staff(provider)
      user_id = user_fixture().id

      assert {:ok, accepted} = Provider.accept_staff_invitation(staff, user_id)
      assert accepted.invitation_status == :accepted
    end

    test "re-fetches fresh state — a stale :sent struct whose DB row is :expired cannot resurrect" do
      provider = provider_profile_fixture()
      stale = sent_staff(provider)
      user_id = user_fixture().id

      # The DB row expires after the caller captured the :sent struct.
      assert {:ok, _} = Provider.expire_staff_invitation(stale)
      assert stale.invitation_status == :sent

      # Accepting with the stale :sent struct must read the fresh :expired state and
      # refuse — not blindly transition the in-memory :sent → :accepted (resurrection).
      assert {:error, :invalid_invitation_transition} =
               AcceptStaffInvitation.execute(stale, user_id)

      assert {:ok, db} = Provider.get_staff_member(stale.id)
      assert db.invitation_status == :expired
      assert is_nil(db.user_id)
    end
  end
end
