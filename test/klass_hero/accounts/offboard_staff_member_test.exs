defmodule KlassHero.Accounts.OffboardStaffMemberTest do
  @moduledoc """
  Durable `:staff` teardown when someone's last employment ends (#972, #1292).

  Offboarding a linked StaffMember removes `:staff` from the owning user's
  `intended_roles` ONLY when no other **active** linked row remains for them at
  any provider. Multi-employer users keep the role (ADR-0005); unlinked
  display-only rows never touch roles. The employment write, the assignment
  teardown and the role removal are one atomic transaction.

  This replaced a hard delete. The role check keys on
  `Provider.get_active_staff_member_by_user/1`, which reads `active` rather than
  row existence, so it kept working unchanged when the row started surviving.
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

  describe "offboard_staff_member/2 — last active linked row" do
    test "ends the employment and removes :staff from the user" do
      user = user_fixture(intended_roles: [:staff])
      staff = linked_staff_row(user, "Only Employer")

      assert {:ok, offboarded} = Accounts.offboard_staff_member(staff.provider_id, staff.id)

      refute offboarded.active
      assert {:ok, %{active: false}} = Provider.get_staff_member(staff.id)
      assert reload_roles(user.id) == []
    end

    test "keeps the row so the roster history survives" do
      user = user_fixture(intended_roles: [:staff])
      staff = linked_staff_row(user, "Only Employer")

      {:ok, _} = Accounts.offboard_staff_member(staff.provider_id, staff.id)

      assert {:ok, kept} = Provider.get_staff_member(staff.id)
      assert kept.first_name == staff.first_name
    end

    test "keeps the user's other roles (provider founder offboarding their self-row)" do
      user = user_fixture(intended_roles: [:provider, :staff])
      staff = linked_staff_row(user, "Their Business")

      assert {:ok, _} = Accounts.offboard_staff_member(staff.provider_id, staff.id)

      assert reload_roles(user.id) == [:provider]
    end
  end

  describe "offboard_staff_member/2 — one of several active rows" do
    test "keeps :staff because another active employment remains" do
      user = user_fixture(intended_roles: [:staff])
      staff_a = linked_staff_row(user, "Alpha Sports")
      _staff_b = linked_staff_row(user, "Beta Camps")

      assert {:ok, _} = Accounts.offboard_staff_member(staff_a.provider_id, staff_a.id)

      assert {:ok, %{active: false}} = Provider.get_staff_member(staff_a.id)
      assert reload_roles(user.id) == [:staff]
    end
  end

  describe "offboard_staff_member/2 — unlinked display-only row" do
    test "ends the employment and never touches roles" do
      provider = provider_profile_fixture(%{business_name: "Some Studio"})
      staff = staff_member_fixture(%{provider_id: provider.id, user_id: nil})

      owner = user_fixture(intended_roles: [:provider, :staff])
      owner_roles_before = reload_roles(owner.id)

      assert {:ok, %{active: false}} = Accounts.offboard_staff_member(staff.provider_id, staff.id)

      assert reload_roles(owner.id) == owner_roles_before
    end
  end

  describe "offboard_staff_member/2 — guards" do
    test "returns :not_found and changes no roles" do
      user = user_fixture(intended_roles: [:staff])

      assert {:error, :not_found} =
               Accounts.offboard_staff_member(Ecto.UUID.generate(), Ecto.UUID.generate())

      assert reload_roles(user.id) == [:staff]
    end

    test "a foreign provider_id offboards nothing and revokes no role" do
      user = user_fixture(intended_roles: [:staff])
      staff = linked_staff_row(user, "Victim Employer")
      other = provider_profile_fixture(%{business_name: "Attacker"})

      assert {:error, :not_found} = Accounts.offboard_staff_member(other.id, staff.id)

      assert {:ok, %{active: true}} = Provider.get_staff_member(staff.id)
      assert reload_roles(user.id) == [:staff]
    end
  end
end
