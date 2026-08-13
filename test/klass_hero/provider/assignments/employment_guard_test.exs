defmodule KlassHero.Provider.Assignments.EmploymentGuardTest do
  @moduledoc """
  The module-wide employment policy for `Provider.Assignments` (#1306).

  Sibling to `OwnershipGuardTest`, and deliberately a separate policy: tenancy
  asks "is this row mine?", employment asks "is this person still on staff?".
  They gate different writes, so proving them in one place would hide the split
  that is the whole point.

  The rule has two halves, and the second is the load-bearing one:

    * a **new attachment** (assign, promote to lead) refuses a deactivated member
      and writes no row — previously it succeeded and then rendered nowhere,
      because the read side filters `active`;
    * the **employment lifecycle** (unassign, delete, update) still reaches one —
      offboarding and GDPR erasure target exactly the people the first half
      refuses, so fusing the two getters breaks them.
  """
  use KlassHero.DataCase, async: true

  import Ecto.Query
  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.ProgramStaffAssignment

  setup do
    provider = insert(:provider_profile_schema)
    staff = insert(:staff_member_schema, provider_id: provider.id)

    %{
      provider: provider,
      program: insert(:program_schema, provider_id: provider.id),
      staff: staff,
      deactivated: insert(:staff_member_schema, provider_id: provider.id, active: false)
    }
  end

  describe "new attachments" do
    test "every row-creating write refuses a deactivated staff member", ctx do
      writes = [
        {"assign_staff_to_program",
         fn ->
           Provider.assign_staff_to_program(%{
             provider_id: ctx.provider.id,
             program_id: ctx.program.id,
             staff_member_id: ctx.deactivated.id
           })
         end},
        {"set_lead_instructor",
         fn -> Provider.set_lead_instructor(ctx.program.id, ctx.deactivated.id, ctx.provider.id) end}
      ]

      for {label, call} <- writes do
        assert call.() == {:error, :not_found}, "#{label}: expected {:error, :not_found}"

        # The bug was a write that *succeeded* invisibly, so the error tuple alone
        # would not have caught it — assert the row is absent.
        refute assignments_for?(ctx.deactivated.id),
               "#{label}: an assignment row was written for a deactivated staff member"
      end
    end

    test "deactivated is indistinguishable from foreign and missing", ctx do
      other = insert(:provider_profile_schema)
      foreign_staff = insert(:staff_member_schema, provider_id: other.id)

      deactivated = Provider.set_lead_instructor(ctx.program.id, ctx.deactivated.id, ctx.provider.id)
      foreign = Provider.set_lead_instructor(ctx.program.id, foreign_staff.id, ctx.provider.id)
      missing = Provider.set_lead_instructor(ctx.program.id, Ecto.UUID.generate(), ctx.provider.id)

      assert deactivated == foreign
      assert foreign == missing
    end

    test "a member deactivated after assignment keeps the assignment but cannot be re-promoted", ctx do
      {:ok, _} =
        Provider.assign_staff_to_program(%{
          provider_id: ctx.provider.id,
          program_id: ctx.program.id,
          staff_member_id: ctx.staff.id
        })

      {:ok, _} = Provider.deactivate_staff_member(ctx.staff)

      # Deactivation deliberately leaves the assignment alive so Messaging
      # membership survives reactivation — only *new* attachments are blocked.
      assert %ProgramStaffAssignment{unassigned_at: nil} =
               Repo.get_by(ProgramStaffAssignment, program_id: ctx.program.id, staff_member_id: ctx.staff.id)

      assert {:error, :not_found} =
               Provider.set_lead_instructor(ctx.program.id, ctx.staff.id, ctx.provider.id)
    end
  end

  describe "employment lifecycle" do
    # The regression guard. If someone later "simplifies" get_staff_member/2 and
    # get_active_staff_member/2 into one getter, these fail — which is the point.
    test "unassign still reaches a member deactivated after assignment", ctx do
      {:ok, _} =
        Provider.assign_staff_to_program(%{
          provider_id: ctx.provider.id,
          program_id: ctx.program.id,
          staff_member_id: ctx.staff.id
        })

      {:ok, _} = Provider.deactivate_staff_member(ctx.staff)

      assert {:ok, _} = Provider.unassign_staff_from_program(ctx.program.id, ctx.staff.id, ctx.provider.id)

      assert %ProgramStaffAssignment{unassigned_at: %DateTime{}} =
               Repo.get_by(ProgramStaffAssignment, program_id: ctx.program.id, staff_member_id: ctx.staff.id)
    end

    test "delete still reaches a deactivated member (offboarding, GDPR erasure)", ctx do
      assert :ok = Provider.delete_staff_member(ctx.deactivated.id, ctx.provider.id)
      assert {:error, :not_found} = Provider.get_staff_member(ctx.deactivated.id, ctx.provider.id)
    end

    test "update still reaches a deactivated member", ctx do
      assert {:ok, updated} =
               Provider.update_staff_member(ctx.provider.id, ctx.deactivated.id, %{role: "Retired Coach"})

      assert updated.role == "Retired Coach"
    end
  end

  defp assignments_for?(staff_member_id) do
    Repo.exists?(from a in ProgramStaffAssignment, where: a.staff_member_id == ^staff_member_id)
  end
end
