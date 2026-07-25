defmodule KlassHero.Provider.Staff.GetStaffMemberScopedTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.StaffMember

  describe "get_staff_member/2 (provider-scoped)" do
    setup do
      provider = insert(:provider_profile_schema)
      other_provider = insert(:provider_profile_schema)
      staff = insert(:staff_member_schema, provider_id: provider.id)

      %{provider: provider, other_provider: other_provider, staff: staff}
    end

    test "returns the staff member when owned by the provider", ctx do
      assert {:ok, %StaffMember{id: id}} = Provider.get_staff_member(ctx.staff.id, ctx.provider.id)
      assert id == ctx.staff.id
    end

    test "loads the pay rate, matching the unscoped getter", ctx do
      assert {:ok, scoped} = Provider.get_staff_member(ctx.staff.id, ctx.provider.id)
      assert {:ok, unscoped} = Provider.get_staff_member(ctx.staff.id)

      assert scoped.pay_rate == unscoped.pay_rate
    end

    test "returns not_found for a staff member owned by another provider", ctx do
      assert {:error, :not_found} = Provider.get_staff_member(ctx.staff.id, ctx.other_provider.id)
    end

    test "returns not_found for a staff member that does not exist", ctx do
      assert {:error, :not_found} = Provider.get_staff_member(Ecto.UUID.generate(), ctx.provider.id)
    end

    # staff_id reaches here straight from phx-value-id, so a malformed one must
    # not crash the LiveView.
    test "returns not_found for a malformed id instead of raising", ctx do
      assert {:error, :not_found} = Provider.get_staff_member("not-a-uuid", ctx.provider.id)
    end

    test "foreign and missing are indistinguishable (no existence oracle)", ctx do
      foreign = Provider.get_staff_member(ctx.staff.id, ctx.other_provider.id)
      missing = Provider.get_staff_member(Ecto.UUID.generate(), ctx.other_provider.id)

      assert foreign == missing
    end
  end
end
