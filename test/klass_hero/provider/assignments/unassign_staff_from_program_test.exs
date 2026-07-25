defmodule KlassHero.Provider.Assignments.UnassignStaffFromProgramTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.ProgramStaffAssignment

  setup do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    staff = insert(:staff_member_schema, provider_id: provider.id)

    %{provider: provider, program: program, staff: staff}
  end

  describe "unassign_staff_from_program/3" do
    test "unassigns an active assignment and sets unassigned_at", ctx do
      assign!(ctx)

      assert {:ok, %ProgramStaffAssignment{} = assignment} =
               Provider.unassign_staff_from_program(ctx.program.id, ctx.staff.id, ctx.provider.id)

      assert assignment.staff_member_id == ctx.staff.id
      assert assignment.program_id == ctx.program.id
      assert %DateTime{} = assignment.unassigned_at
    end

    test "returns not_found when no active assignment exists", ctx do
      assert {:error, :not_found} =
               Provider.unassign_staff_from_program(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 ctx.provider.id
               )
    end

    test "returns not_found when assignment was already unassigned", ctx do
      assign!(ctx)

      assert {:ok, _} =
               Provider.unassign_staff_from_program(ctx.program.id, ctx.staff.id, ctx.provider.id)

      assert {:error, :not_found} =
               Provider.unassign_staff_from_program(ctx.program.id, ctx.staff.id, ctx.provider.id)
    end
  end

  # Cross-tenant rejection is asserted module-wide in ownership_guard_test.exs.

  defp assign!(ctx) do
    {:ok, assignment} =
      Provider.assign_staff_to_program(%{
        provider_id: ctx.provider.id,
        program_id: ctx.program.id,
        staff_member_id: ctx.staff.id
      })

    assignment
  end
end
