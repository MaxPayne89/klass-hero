defmodule KlassHero.Provider.Assignments.ListPublicStaffForProgramTest do
  @moduledoc """
  The roster behind the public `/programs/:id` "Meet the Heroes" section.

  Same assignment rules as `list_active_staff_for_program/1`, plus one: the seat
  must be claimed. The two functions exist side by side rather than as one
  narrowed query because the unnarrowed one feeds the provider's staffing modal,
  which has to keep showing people whose invitations are still outstanding.
  """
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider

  setup do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)

    shown = claimed_staff(provider.id)
    unclaimed = insert(:staff_member_schema, provider_id: provider.id, user_id: nil)
    deactivated = claimed_staff(provider.id)
    released = claimed_staff(provider.id)
    unassigned = claimed_staff(provider.id)

    for staff <- [shown, unclaimed, deactivated, released] do
      assign!(provider.id, program.id, staff.id)
    end

    {:ok, deactivated} = Provider.deactivate_staff_member(deactivated)
    {:ok, _} = Provider.unassign_staff_from_program(program.id, released.id, provider.id)

    %{
      provider: provider,
      program: program,
      shown: shown,
      unclaimed: unclaimed,
      deactivated: deactivated,
      released: released,
      unassigned: unassigned
    }
  end

  describe "list_public_staff_for_program/1" do
    test "returns exactly the claimed, active, currently-assigned staff", ctx do
      assert [%{id: id}] = Provider.list_public_staff_for_program(ctx.program.id)
      assert id == ctx.shown.id
    end

    test "excludes every shape a public page must not name", ctx do
      ids = ids_for(ctx.program)

      for {reason, excluded} <- [
            {"an invitation nobody claimed", ctx.unclaimed},
            {"an employment that ended", ctx.deactivated},
            {"an assignment that was released", ctx.released},
            {"a colleague never assigned to this program", ctx.unassigned}
          ] do
        refute excluded.id in ids, "#{reason} leaked onto the public program page"
      end
    end

    # The narrowing is the ONLY difference. Pinning it as a set difference means
    # a drift in the shared assignment rules shows here as well as in the
    # sibling's own tests, rather than the two quietly diverging.
    test "differs from the management read by the unclaimed staff alone", ctx do
      managed = ctx.program.id |> Provider.list_active_staff_for_program() |> Enum.map(& &1.id)

      assert MapSet.difference(MapSet.new(managed), MapSet.new(ids_for(ctx.program))) ==
               MapSet.new([ctx.unclaimed.id])
    end
  end

  defp ids_for(program) do
    program.id |> Provider.list_public_staff_for_program() |> Enum.map(& &1.id)
  end

  defp claimed_staff(provider_id) do
    insert(:staff_member_schema,
      provider_id: provider_id,
      user_id: AccountsFixtures.user_fixture().id,
      invitation_status: :accepted
    )
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
