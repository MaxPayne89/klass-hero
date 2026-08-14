defmodule KlassHero.Provider.Staff.DeleteStaffMemberTest do
  @moduledoc """
  `delete_staff_member/2` — the narrow hard delete that survives #1292.

  Removing a real employee is `offboard_staff_member/1`; this is the eraser for a
  row that is provably a data-entry mistake. The precondition is what makes the
  destruction safe: no linked user, no invitation ever sent, and no assignment
  row ever created. Anything else has left a trace somewhere — an event naming
  this `staff_member_id`, or an email that told a real person they had a role at
  this business — and deleting the row would leave those pointing at nothing,
  which is the class of defect #1292 was.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.StaffMember
  alias KlassHero.ProviderFixtures

  setup do
    provider = ProviderFixtures.provider_profile_fixture()
    staff = insert(:staff_member_schema, provider_id: provider.id)
    %{provider: provider, staff: staff}
  end

  describe "delete_staff_member/2 on a row with no history" do
    test "deletes it", ctx do
      assert :ok = Provider.delete_staff_member(ctx.staff.id, ctx.provider.id)
      assert {:error, :not_found} = Provider.get_staff_member(ctx.staff.id)
    end

    test "does not affect other staff members", ctx do
      other = insert(:staff_member_schema, provider_id: ctx.provider.id)

      assert :ok = Provider.delete_staff_member(ctx.staff.id, ctx.provider.id)

      assert {:ok, _} = Provider.get_staff_member(other.id)
    end

    test "returns not_found for a staff member that does not exist", ctx do
      assert {:error, :not_found} = Provider.delete_staff_member(Ecto.UUID.generate(), ctx.provider.id)
    end
  end

  describe "delete_staff_member/2 on a row with history" do
    setup ctx do
      user = KlassHero.AccountsFixtures.user_fixture()
      program = insert(:program_schema, provider_id: ctx.provider.id)

      %{user: user, program: program}
    end

    # Each trace is independently disqualifying, so they are proven one at a
    # time rather than on one maximally-dirty row — a single fixture carrying all
    # three would pass even if only one of the checks were implemented.
    for {trace, description} <- [
          {:linked, "a linked user account"},
          {:invited, "an invitation that was sent"},
          {:expired_invite, "an invitation that expired unclaimed"},
          {:assigned, "a live program assignment"},
          {:unassigned, "a program assignment that was later retired"}
        ] do
      test "refuses a row carrying #{description}", ctx do
        staff = dirty_staff(unquote(trace), ctx)

        assert {:error, :has_history} = Provider.delete_staff_member(staff.id, ctx.provider.id),
               "expected #{unquote(description)} to disqualify the row from hard deletion"

        assert %StaffMember{} = Repo.get(StaffMember, staff.id)
      end
    end
  end

  describe "delete_staff_member/2 IDOR guards" do
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

  defp dirty_staff(:linked, ctx), do: insert(:staff_member_schema, provider_id: ctx.provider.id, user_id: ctx.user.id)

  defp dirty_staff(:invited, ctx),
    do: insert(:staff_member_schema, provider_id: ctx.provider.id, invitation_status: :sent)

  defp dirty_staff(:expired_invite, ctx),
    do: insert(:staff_member_schema, provider_id: ctx.provider.id, invitation_status: :expired)

  defp dirty_staff(:assigned, ctx) do
    staff = insert(:staff_member_schema, provider_id: ctx.provider.id)

    {:ok, _} =
      Provider.assign_staff_to_program(%{
        provider_id: ctx.provider.id,
        program_id: ctx.program.id,
        staff_member_id: staff.id
      })

    staff
  end

  defp dirty_staff(:unassigned, ctx) do
    staff = dirty_staff(:assigned, ctx)
    {:ok, _} = Provider.unassign_staff_from_program(ctx.program.id, staff.id, ctx.provider.id)

    staff
  end
end
