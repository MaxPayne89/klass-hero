defmodule KlassHero.Provider.Staff.DeleteStaffMemberTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider
  alias KlassHero.ProviderFixtures

  setup do
    provider = ProviderFixtures.provider_profile_fixture()
    staff = ProviderFixtures.staff_member_fixture(provider_id: provider.id)
    %{staff: staff}
  end

  describe "execute/1" do
    test "deletes an existing staff member", %{staff: staff} do
      assert :ok = Provider.delete_staff_member(staff.id)
      assert {:error, :not_found} = Provider.get_staff_member(staff.id)
    end

    test "returns :not_found for non-existent staff member" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = Provider.delete_staff_member(fake_id)
    end

    test "does not affect other staff members", %{staff: staff} do
      provider_id = staff.provider_id
      other_staff = ProviderFixtures.staff_member_fixture(provider_id: provider_id)

      assert :ok = Provider.delete_staff_member(staff.id)

      assert {:ok, _} = Provider.get_staff_member(other_staff.id)
    end
  end
end
