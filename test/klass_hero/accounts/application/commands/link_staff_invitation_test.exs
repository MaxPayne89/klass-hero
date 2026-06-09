defmodule KlassHero.Accounts.Application.Commands.LinkStaffInvitationTest do
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
end
