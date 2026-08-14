defmodule KlassHero.Accounts.RemoveStaffMemberTest do
  @moduledoc """
  `remove_staff_member/2` — the narrow erase of a mis-typed roster entry (#1292).

  Ending a real employment is `offboard_staff_member/2`, which keeps the row and
  tears the person out of their programs' conversations. This one destroys the
  row, so it only accepts a row with no history to destroy: no linked user, no
  invitation ever sent, no assignment ever created.

  The `:staff` role teardown it inherited from #972 is now unreachable by
  construction — a row eligible for erasure has no `user_id` — but the branch
  stays, because a future relaxation of the precondition would need it back.
  """
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.ProviderFixtures

  alias KlassHero.Accounts
  alias KlassHero.Accounts.User
  alias KlassHero.Provider

  defp reload_roles(user_id), do: Repo.get!(User, user_id).intended_roles

  describe "remove_staff_member/2 — unlinked display-only row" do
    test "deletes the row and never touches roles" do
      # No user_id, no invitation: a roster entry typed in by hand and regretted.
      provider = provider_profile_fixture(%{business_name: "Some Studio"})
      staff = staff_member_fixture(%{provider_id: provider.id, user_id: nil})

      owner = user_fixture(intended_roles: [:provider, :staff])
      owner_roles_before = reload_roles(owner.id)

      assert {:ok, _deleted} = Accounts.remove_staff_member(staff.provider_id, staff.id)

      assert {:error, :not_found} = Provider.get_staff_member(staff.id)
      assert reload_roles(owner.id) == owner_roles_before
    end
  end

  describe "remove_staff_member/2 — a row with history" do
    test "refuses a linked row and leaves the user's roles alone" do
      user = user_fixture(intended_roles: [:staff])
      provider = provider_profile_fixture(%{business_name: "Real Employer"})

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          user_id: user.id,
          active: true,
          invitation_status: :accepted
        })

      assert {:error, :has_history} = Accounts.remove_staff_member(provider.id, staff.id)

      assert {:ok, %{active: true}} = Provider.get_staff_member(staff.id)
      assert reload_roles(user.id) == [:staff]
    end
  end

  describe "remove_staff_member/2 — guards" do
    test "returns :not_found and changes no roles" do
      user = user_fixture(intended_roles: [:staff])

      assert {:error, :not_found} =
               Accounts.remove_staff_member(Ecto.UUID.generate(), Ecto.UUID.generate())

      assert reload_roles(user.id) == [:staff]
    end

    test "a foreign provider_id deletes nothing (IDOR guard)" do
      provider = provider_profile_fixture(%{business_name: "Victim Studio"})
      staff = staff_member_fixture(%{provider_id: provider.id, user_id: nil})
      other = provider_profile_fixture(%{business_name: "Attacker"})

      # Indistinguishable from a genuine miss — no existence leak.
      assert {:error, :not_found} = Accounts.remove_staff_member(other.id, staff.id)

      assert {:ok, _still_there} = Provider.get_staff_member(staff.id)
    end
  end
end
