defmodule KlassHero.Accounts.LinkStaffInvitationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.ProviderFixtures

  alias KlassHero.Accounts
  alias KlassHero.Accounts.User
  alias KlassHero.Provider

  defp sent_staff_for(provider, email) do
    staff_member_fixture(%{
      provider_id: provider.id,
      email: email,
      invitation_status: :sent,
      invitation_token_hash: :crypto.hash(:sha256, "tok-#{System.unique_integer([:positive])}"),
      invitation_sent_at: DateTime.utc_now()
    })
  end

  defp reload_roles(user_id), do: Repo.get!(User, user_id).intended_roles

  describe "link_staff_invitation/2 (happy path)" do
    test "appends :staff and links the StaffMember, preserving existing roles" do
      user = user_fixture(intended_roles: [:parent])
      provider = provider_profile_fixture()
      staff = sent_staff_for(provider, user.email)

      assert {:ok, updated} = Accounts.link_staff_invitation(user, staff)

      assert updated.intended_roles == [:parent, :staff]
      assert reload_roles(user.id) == [:parent, :staff]

      assert {:ok, linked} = Provider.get_staff_member(staff.id)
      assert linked.user_id == user.id
      assert linked.invitation_status == :accepted
    end
  end

  describe "link_staff_invitation/2 (email mismatch)" do
    test "returns :email_mismatch and performs no writes" do
      user = user_fixture(intended_roles: [:parent])
      provider = provider_profile_fixture()
      staff = sent_staff_for(provider, "someone-else@example.com")

      assert {:error, :email_mismatch} = Accounts.link_staff_invitation(user, staff)

      # No role granted, no link made.
      assert reload_roles(user.id) == [:parent]
      assert {:ok, untouched} = Provider.get_staff_member(staff.id)
      assert untouched.invitation_status == :sent
      assert is_nil(untouched.user_id)
    end

    test "matches case-insensitively, ignoring surrounding whitespace" do
      user = user_fixture(intended_roles: [:parent])
      provider = provider_profile_fixture()
      staff = sent_staff_for(provider, " #{String.upcase(user.email)} ")

      assert {:ok, _updated} = Accounts.link_staff_invitation(user, staff)
    end
  end

  describe "link_staff_invitation/2 (stale session struct)" do
    test "a role granted after the struct was loaded survives the link" do
      user = user_fixture(intended_roles: [:parent])
      provider = provider_profile_fixture()
      staff = sent_staff_for(provider, user.email)

      # Another flow grants :provider after this session's struct was loaded —
      # the command must not write the stale array back.
      {1, _} =
        Repo.update_all(from(u in User, where: u.id == ^user.id),
          set: [intended_roles: ["parent", "provider"]]
        )

      assert {:ok, updated} = Accounts.link_staff_invitation(user, staff)

      assert :provider in updated.intended_roles
      assert :staff in updated.intended_roles
      assert :provider in reload_roles(user.id)
    end
  end

  describe "link_staff_invitation/2 (atomic — no partial state)" do
    test "a failed link grants no role and leaves the invitation untouched" do
      user = user_fixture(intended_roles: [:parent])
      provider = provider_profile_fixture()
      staff = sent_staff_for(provider, user.email)

      # Expire the invitation so the link step fails its state transition.
      assert {:ok, _} = Provider.expire_staff_invitation(staff)

      assert {:error, :invalid_invitation_transition} =
               Accounts.link_staff_invitation(user, staff)

      # No :staff granted (role only follows a successful link), invitation unchanged.
      assert reload_roles(user.id) == [:parent]
      assert {:ok, db} = Provider.get_staff_member(staff.id)
      assert db.invitation_status == :expired
      assert is_nil(db.user_id)
    end
  end
end
