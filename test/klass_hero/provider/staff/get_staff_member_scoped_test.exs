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

    # The division of labour with get_active_staff_member/2 below: this getter
    # answers tenancy only, so the lifecycle paths built on it (edit, delete,
    # unassign, GDPR erasure) keep reaching an offboarded member. #1306.
    test "still returns a deactivated staff member", ctx do
      deactivated = insert(:staff_member_schema, provider_id: ctx.provider.id, active: false)

      assert {:ok, %StaffMember{id: id}} = Provider.get_staff_member(deactivated.id, ctx.provider.id)
      assert id == deactivated.id
    end
  end

  describe "get_active_staff_member/2 (provider-scoped + employed)" do
    setup do
      provider = insert(:provider_profile_schema)
      other_provider = insert(:provider_profile_schema)
      staff = insert(:staff_member_schema, provider_id: provider.id)

      %{provider: provider, other_provider: other_provider, staff: staff}
    end

    test "returns the staff member when owned by the provider and active", ctx do
      assert {:ok, %StaffMember{id: id}} = Provider.get_active_staff_member(ctx.staff.id, ctx.provider.id)
      assert id == ctx.staff.id
    end

    # `deactivated` is the #1306 case: the attach paths accepted such a member,
    # wrote a real row, and the read side then filtered them out of every render.
    # A malformed id reaches here straight from phx-value, so it must not raise.
    test "returns not_found for every unattachable id", ctx do
      deactivated = insert(:staff_member_schema, provider_id: ctx.provider.id, active: false)

      cases = [
        {"deactivated", deactivated.id, ctx.provider.id},
        {"foreign", ctx.staff.id, ctx.other_provider.id},
        {"missing", Ecto.UUID.generate(), ctx.provider.id},
        {"malformed", "not-a-uuid", ctx.provider.id}
      ]

      for {label, staff_id, provider_id} <- cases do
        assert Provider.get_active_staff_member(staff_id, provider_id) == {:error, :not_found},
               "#{label}: expected {:error, :not_found}"
      end
    end

    test "loads the pay rate, matching the tenancy-only getter", ctx do
      assert {:ok, active_only} = Provider.get_active_staff_member(ctx.staff.id, ctx.provider.id)
      assert {:ok, scoped} = Provider.get_staff_member(ctx.staff.id, ctx.provider.id)

      assert active_only.pay_rate == scoped.pay_rate
    end

    # Deactivated collapses into the same answer as foreign and missing, so no
    # caller learns that the id was real — and none needs a third error branch.
    test "deactivated, foreign and missing are indistinguishable", ctx do
      deactivated = insert(:staff_member_schema, provider_id: ctx.provider.id, active: false)

      inactive = Provider.get_active_staff_member(deactivated.id, ctx.provider.id)
      foreign = Provider.get_active_staff_member(ctx.staff.id, ctx.other_provider.id)
      missing = Provider.get_active_staff_member(Ecto.UUID.generate(), ctx.provider.id)

      assert inactive == foreign
      assert foreign == missing
    end
  end
end
