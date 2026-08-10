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

  # The lead guard below makes a retired-yet-lead row unreachable through the
  # facade, so the changeset keeps its own belt-and-braces clear — asserted here
  # rather than through unassign_staff_from_program/3, where the flag would
  # already be false before the call and the assertion would prove nothing.
  describe "ProgramStaffAssignment.unassign_changeset/1" do
    test "clears a lead flag it finds set" do
      assignment = %ProgramStaffAssignment{is_lead_instructor: true}

      changeset = ProgramStaffAssignment.unassign_changeset(assignment)

      assert Ecto.Changeset.get_change(changeset, :is_lead_instructor) == false
      assert %DateTime{} = Ecto.Changeset.get_change(changeset, :unassigned_at)
    end
  end

  describe "unassign_staff_from_program/3 lead guard" do
    setup ctx do
      assign!(ctx)
      {:ok, _lead} = Provider.set_lead_instructor(ctx.program.id, ctx.staff.id, ctx.provider.id)
      :ok
    end

    test "refuses to retire the program's lead instructor", ctx do
      assert {:error, :cannot_unassign_lead} =
               Provider.unassign_staff_from_program(ctx.program.id, ctx.staff.id, ctx.provider.id)
    end

    test "leaves the assignment active after refusing", ctx do
      Provider.unassign_staff_from_program(ctx.program.id, ctx.staff.id, ctx.provider.id)

      assert %{id: staff_id} = Provider.get_lead_instructor(ctx.program.id)
      assert staff_id == ctx.staff.id
    end

    test "allows the retirement once the lead has been cleared", ctx do
      :ok = Provider.clear_lead_instructor(ctx.program.id, ctx.provider.id)

      assert {:ok, _} =
               Provider.unassign_staff_from_program(ctx.program.id, ctx.staff.id, ctx.provider.id)
    end

    test "does not block retiring a colleague who is not the lead", ctx do
      other = insert(:staff_member_schema, provider_id: ctx.provider.id)

      {:ok, _} =
        Provider.assign_staff_to_program(%{
          provider_id: ctx.provider.id,
          program_id: ctx.program.id,
          staff_member_id: other.id
        })

      assert {:ok, _} =
               Provider.unassign_staff_from_program(ctx.program.id, other.id, ctx.provider.id)
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
