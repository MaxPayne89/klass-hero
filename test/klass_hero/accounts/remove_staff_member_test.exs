defmodule KlassHero.Accounts.RemoveStaffMemberTest do
  @moduledoc """
  Durable `:staff` teardown when the last linked staff row is deleted (#972).

  Deleting a linked StaffMember row removes `:staff` from the owning user's
  `intended_roles` ONLY when no other active linked row remains for them at any
  provider. Multi-employer users keep the role; unlinked display-only rows never
  touch roles. The delete and the role removal are one atomic transaction.
  """
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.ProviderFixtures

  alias KlassHero.Accounts
  alias KlassHero.Accounts.User
  alias KlassHero.Provider

  defp reload_roles(user_id), do: Repo.get!(User, user_id).intended_roles

  defp linked_staff_row(user, business_name) do
    provider = provider_profile_fixture(%{business_name: business_name})

    staff_member_fixture(%{
      provider_id: provider.id,
      user_id: user.id,
      active: true,
      invitation_status: :accepted
    })
  end

  describe "remove_staff_member/1 — last active linked row" do
    test "deletes the row and removes :staff from the user" do
      user = user_fixture(intended_roles: [:staff])
      staff = linked_staff_row(user, "Only Employer")

      assert {:ok, _deleted} = Accounts.remove_staff_member(staff.id)

      assert {:error, :not_found} = Provider.get_staff_member(staff.id)
      assert reload_roles(user.id) == []
    end

    test "keeps the user's other roles (provider founder deleting their self-row)" do
      user = user_fixture(intended_roles: [:provider, :staff])
      staff = linked_staff_row(user, "Their Business")

      assert {:ok, _deleted} = Accounts.remove_staff_member(staff.id)

      assert reload_roles(user.id) == [:provider]
    end
  end

  describe "remove_staff_member/1 — one of several active rows" do
    test "keeps :staff because another active employment remains" do
      user = user_fixture(intended_roles: [:staff])
      staff_a = linked_staff_row(user, "Alpha Sports")
      _staff_b = linked_staff_row(user, "Beta Camps")

      assert {:ok, _deleted} = Accounts.remove_staff_member(staff_a.id)

      assert {:error, :not_found} = Provider.get_staff_member(staff_a.id)
      assert reload_roles(user.id) == [:staff]
    end
  end

  describe "remove_staff_member/1 — unlinked display-only row" do
    test "deletes the row and never touches roles" do
      # No user_id: an invited-but-unaccepted / email-less staff entry. The
      # provider who created it keeps their own roles untouched.
      provider = provider_profile_fixture(%{business_name: "Some Studio"})
      staff = staff_member_fixture(%{provider_id: provider.id, user_id: nil})

      owner = user_fixture(intended_roles: [:provider, :staff])
      owner_roles_before = reload_roles(owner.id)

      assert {:ok, _deleted} = Accounts.remove_staff_member(staff.id)

      assert {:error, :not_found} = Provider.get_staff_member(staff.id)
      assert reload_roles(owner.id) == owner_roles_before
    end
  end

  describe "remove_staff_member/1 — not found" do
    test "returns :not_found and changes no roles" do
      user = user_fixture(intended_roles: [:staff])

      assert {:error, :not_found} = Accounts.remove_staff_member(Ecto.UUID.generate())

      assert reload_roles(user.id) == [:staff]
    end
  end
end
