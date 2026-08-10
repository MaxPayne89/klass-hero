defmodule KlassHero.Provider.Assignments.ListAssignableStaffForProgramTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider

  # One fixture covering every exclusion rule at once, so a regression in any
  # single rule shows up as a diff on one id set rather than a passing test
  # elsewhere. Named bindings, not a table: each case needs its own setup shape.
  setup do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)

    free = insert(:staff_member_schema, provider_id: provider.id)
    assigned = insert(:staff_member_schema, provider_id: provider.id)
    inactive = insert(:staff_member_schema, provider_id: provider.id, active: false)
    released = insert(:staff_member_schema, provider_id: provider.id)

    rival = insert(:provider_profile_schema)
    rival_staff = insert(:staff_member_schema, provider_id: rival.id)

    assign!(provider.id, program.id, assigned.id)

    assign!(provider.id, program.id, released.id)
    {:ok, _} = Provider.unassign_staff_from_program(program.id, released.id, provider.id)

    %{
      provider: provider,
      program: program,
      free: free,
      assigned: assigned,
      inactive: inactive,
      released: released,
      rival_staff: rival_staff
    }
  end

  describe "list_assignable_staff_for_program/2" do
    test "offers exactly the provider's active, not-currently-assigned staff", ctx do
      ids = assignable_ids(ctx)

      assert ids == MapSet.new([ctx.free.id, ctx.released.id])
    end

    test "excludes staff already holding an active assignment", ctx do
      refute MapSet.member?(assignable_ids(ctx), ctx.assigned.id)
    end

    test "excludes deactivated staff", ctx do
      refute MapSet.member?(assignable_ids(ctx), ctx.inactive.id)
    end

    test "excludes another provider's staff", ctx do
      refute MapSet.member?(assignable_ids(ctx), ctx.rival_staff.id)
    end

    test "re-offers staff whose previous assignment was retired", ctx do
      assert MapSet.member?(assignable_ids(ctx), ctx.released.id)
    end

    test "returns an empty list once every active staff member is on the program", ctx do
      fully_staffed = insert(:program_schema, provider_id: ctx.provider.id)

      for staff <- [ctx.free, ctx.assigned, ctx.released] do
        assign!(ctx.provider.id, fully_staffed.id, staff.id)
      end

      assert Provider.list_assignable_staff_for_program(ctx.provider.id, fully_staffed.id) == []
    end
  end

  defp assignable_ids(ctx) do
    ctx.provider.id
    |> Provider.list_assignable_staff_for_program(ctx.program.id)
    |> MapSet.new(& &1.id)
  end

  defp assign!(provider_id, program_id, staff_member_id) do
    {:ok, assignment} =
      Provider.assign_staff_to_program(%{
        provider_id: provider_id,
        program_id: program_id,
        staff_member_id: staff_member_id
      })

    assignment
  end
end
