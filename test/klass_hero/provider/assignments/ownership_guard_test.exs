defmodule KlassHero.Provider.Assignments.OwnershipGuardTest do
  @moduledoc """
  The module-wide tenancy policy for `Provider.Assignments`.

  Every write proves the same rule from a single place: a foreign staff member or
  a foreign program is indistinguishable from a missing one, and no cross-tenant
  row is ever written. Per-function edge cases (already-assigned, idempotent
  re-promotion, ...) stay in the per-function test files.
  """
  use KlassHero.DataCase, async: true

  import Ecto.Query
  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.ProgramStaffAssignment

  setup do
    provider = insert(:provider_profile_schema)
    other = insert(:provider_profile_schema)

    %{
      provider: provider,
      program: insert(:program_schema, provider_id: provider.id),
      staff: insert(:staff_member_schema, provider_id: provider.id),
      foreign_program: insert(:program_schema, provider_id: other.id),
      foreign_staff: insert(:staff_member_schema, provider_id: other.id)
    }
  end

  describe "cross-tenant writes" do
    test "every row-creating write rejects a foreign staff member or program", ctx do
      # {label, call, program the row would have landed on}
      writes = [
        {"assign_staff_to_program/foreign staff",
         fn ->
           Provider.assign_staff_to_program(%{
             provider_id: ctx.provider.id,
             program_id: ctx.program.id,
             staff_member_id: ctx.foreign_staff.id
           })
         end, ctx.program.id},
        {"assign_staff_to_program/foreign program",
         fn ->
           Provider.assign_staff_to_program(%{
             provider_id: ctx.provider.id,
             program_id: ctx.foreign_program.id,
             staff_member_id: ctx.staff.id
           })
         end, ctx.foreign_program.id},
        {"set_lead_instructor/foreign staff",
         fn ->
           Provider.set_lead_instructor(ctx.program.id, ctx.foreign_staff.id, ctx.provider.id)
         end, ctx.program.id},
        {"set_lead_instructor/foreign program",
         fn ->
           Provider.set_lead_instructor(ctx.foreign_program.id, ctx.staff.id, ctx.provider.id)
         end, ctx.foreign_program.id}
      ]

      for {label, call, program_id} <- writes do
        assert call.() == {:error, :not_found}, "#{label}: expected {:error, :not_found}"

        refute assignments_on?(program_id),
               "#{label}: a cross-tenant assignment row was written"
      end
    end

    test "a missing staff member or program is indistinguishable from a foreign one", ctx do
      missing_id = Ecto.UUID.generate()

      assert Provider.set_lead_instructor(ctx.program.id, missing_id, ctx.provider.id) ==
               Provider.set_lead_instructor(ctx.program.id, ctx.foreign_staff.id, ctx.provider.id)

      assert Provider.set_lead_instructor(missing_id, ctx.staff.id, ctx.provider.id) ==
               Provider.set_lead_instructor(ctx.foreign_program.id, ctx.staff.id, ctx.provider.id)
    end

    # The remaining two writes mutate existing rows rather than creating them, so
    # each asserts on the row it must NOT have touched — not foldable into the
    # table above, and `clear_lead_instructor` returns :ok either way by design.
    test "unassign leaves another provider's assignment active", ctx do
      {:ok, _} =
        Provider.assign_staff_to_program(%{
          provider_id: ctx.provider.id,
          program_id: ctx.program.id,
          staff_member_id: ctx.staff.id
        })

      attacker = insert(:provider_profile_schema)

      assert {:error, :not_found} =
               Provider.unassign_staff_from_program(ctx.program.id, ctx.staff.id, attacker.id)

      assert %ProgramStaffAssignment{unassigned_at: nil} =
               Repo.get_by(ProgramStaffAssignment,
                 program_id: ctx.program.id,
                 staff_member_id: ctx.staff.id
               )
    end

    test "clear_lead_instructor leaves another provider's lead in place", ctx do
      {:ok, _} = Provider.set_lead_instructor(ctx.program.id, ctx.staff.id, ctx.provider.id)
      attacker = insert(:provider_profile_schema)

      assert :ok = Provider.clear_lead_instructor(ctx.program.id, attacker.id)
      assert %{id: lead_id} = Provider.get_lead_instructor(ctx.program.id)
      assert lead_id == ctx.staff.id
    end
  end

  defp assignments_on?(program_id) do
    Repo.exists?(from a in ProgramStaffAssignment, where: a.program_id == ^program_id)
  end
end
