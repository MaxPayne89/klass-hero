defmodule KlassHero.Provider.Staff.AcceptStaffInvitationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.ProviderFixtures

  alias KlassHero.Provider

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

      assert {:ok, accepted} = Provider.accept_staff_invitation(staff, user_id)
      assert accepted.invitation_status == :accepted
      assert accepted.user_id == user_id
    end

    test "is idempotent — re-accepting by the same user is a no-op success" do
      provider = provider_profile_fixture()
      staff = sent_staff(provider)
      user_id = user_fixture().id

      assert {:ok, accepted} = Provider.accept_staff_invitation(staff, user_id)
      assert {:ok, again} = Provider.accept_staff_invitation(accepted, user_id)

      assert again.invitation_status == :accepted
      assert again.user_id == user_id
    end

    test "supports multi-employer — same user accepts at two different providers" do
      user_id = user_fixture().id
      staff_a = sent_staff(provider_profile_fixture())
      staff_b = sent_staff(provider_profile_fixture())

      assert {:ok, a} = Provider.accept_staff_invitation(staff_a, user_id)
      assert {:ok, b} = Provider.accept_staff_invitation(staff_b, user_id)

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

    test "accepting becomes the selected staff context, beating a prior switcher selection" do
      # Regression (#969 switcher review finding 1): selection ordering ranks
      # last_selected_at above inserted_at, so without a bump on accept the
      # freshly joined employer would lose to any previously selected one and
      # the post-accept redirect would land on the OLD employer's dashboard.
      user = user_fixture(intended_roles: [:staff])
      old_employer = provider_profile_fixture()

      staff_member_fixture(%{
        provider_id: old_employer.id,
        user_id: user.id,
        invitation_status: :accepted,
        last_selected_at: ~U[2026-06-01 09:00:00Z]
      })

      new_employer = provider_profile_fixture()
      invite = sent_staff(new_employer)

      assert {:ok, accepted} = Provider.accept_staff_invitation(invite, user.id)

      assert {:ok, resolved} = Provider.get_active_staff_member_by_user(user.id)
      assert resolved.id == accepted.id
      assert resolved.provider_id == new_employer.id
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
               Provider.accept_staff_invitation(stale, user_id)

      assert {:ok, db} = Provider.get_staff_member(stale.id)
      assert db.invitation_status == :expired
      assert is_nil(db.user_id)
    end
  end
end
