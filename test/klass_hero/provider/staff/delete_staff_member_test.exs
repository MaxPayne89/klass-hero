defmodule KlassHero.Provider.Staff.DeleteStaffMemberTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider
  alias KlassHero.Provider.StaffMember
  alias KlassHero.ProviderFixtures

  setup do
    provider = ProviderFixtures.provider_profile_fixture()
    staff = ProviderFixtures.staff_member_fixture(provider_id: provider.id)
    %{provider: provider, staff: staff}
  end

  describe "delete_staff_member/2" do
    test "deletes a staff member owned by the provider", ctx do
      assert :ok = Provider.delete_staff_member(ctx.staff.id, ctx.provider.id)
      assert {:error, :not_found} = Provider.get_staff_member(ctx.staff.id)
    end

    test "returns not_found for a staff member that does not exist", ctx do
      assert {:error, :not_found} =
               Provider.delete_staff_member(Ecto.UUID.generate(), ctx.provider.id)
    end

    test "does not affect other staff members", ctx do
      other_staff = ProviderFixtures.staff_member_fixture(provider_id: ctx.provider.id)

      assert :ok = Provider.delete_staff_member(ctx.staff.id, ctx.provider.id)

      assert {:ok, _} = Provider.get_staff_member(other_staff.id)
    end

    test "leaves another provider's staff member intact", ctx do
      attacker = ProviderFixtures.provider_profile_fixture()

      assert {:error, :not_found} = Provider.delete_staff_member(ctx.staff.id, attacker.id)

      assert %StaffMember{} = Repo.get(StaffMember, ctx.staff.id)
    end

    test "foreign and missing are indistinguishable (no existence oracle)", ctx do
      attacker = ProviderFixtures.provider_profile_fixture()

      foreign = Provider.delete_staff_member(ctx.staff.id, attacker.id)
      missing = Provider.delete_staff_member(Ecto.UUID.generate(), attacker.id)

      assert foreign == missing
    end
  end
end
