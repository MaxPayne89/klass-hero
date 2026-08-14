defmodule KlassHero.Provider.Assignments.ListActiveStaffUserIdsForProgramTest do
  @moduledoc """
  The read that replaced Messaging's `program_staff_participants` mirror (#1321).

  Every exclusion below was a bug the mirror could express and this read cannot:
  a nil `user_id` crashed the unassign clause (#1309), and a deactivated staff
  member kept passing the broadcast-reply guard because deactivation was never
  routed to the mirror (#1320).
  """
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider

  # One fixture covering every exclusion at once, so a regression in any single
  # rule shows as a diff on one id set rather than passing quietly elsewhere.
  setup do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)

    active = claimed_staff(provider.id)
    deactivated = claimed_staff(provider.id)
    released = claimed_staff(provider.id)
    unclaimed = insert(:staff_member_schema, provider_id: provider.id, user_id: nil)

    rival = insert(:provider_profile_schema)
    rival_program = insert(:program_schema, provider_id: rival.id)
    rival_staff = claimed_staff(rival.id)

    for staff <- [active, deactivated, released, unclaimed] do
      assign!(provider.id, program.id, staff.id)
    end

    assign!(rival.id, rival_program.id, rival_staff.id)

    # Bind the *returned* struct: `reactivate_staff_member/1` short-circuits on
    # `active: true`, so the reactivation case below would silently no-op if the
    # pre-deactivation struct were carried forward.
    {:ok, deactivated} = Provider.deactivate_staff_member(deactivated)
    {:ok, _} = Provider.unassign_staff_from_program(program.id, released.id, provider.id)

    %{
      provider: provider,
      program: program,
      active: active,
      deactivated: deactivated,
      released: released,
      unclaimed: unclaimed,
      rival_staff: rival_staff
    }
  end

  describe "list_active_staff_user_ids_for_program/1" do
    test "returns exactly the claimed, active, currently-assigned staff", ctx do
      assert user_ids(ctx) == MapSet.new([ctx.active.user_id])
    end

    # Each excluded shape was reachable in the mirror; none is expressible here.
    for {label, key} <- [
          {"deactivated staff (#1320)", :deactivated},
          {"staff whose assignment was retired", :released},
          {"unclaimed staff, who have no user id (#1309)", :unclaimed},
          {"another provider's staff", :rival_staff}
        ] do
      test "excludes #{label}", ctx do
        excluded = ctx[unquote(key)]

        refute MapSet.member?(user_ids(ctx), excluded.user_id),
               "expected #{unquote(label)} (user_id #{inspect(excluded.user_id)}) to be excluded"
      end
    end

    test "returns a reactivated staff member again, with no event or replay", ctx do
      refute MapSet.member?(user_ids(ctx), ctx.deactivated.user_id)

      {:ok, _} = Provider.reactivate_staff_member(ctx.deactivated)

      assert MapSet.member?(user_ids(ctx), ctx.deactivated.user_id)
    end

    test "returns an empty list for a program nobody staffs", ctx do
      unstaffed = insert(:program_schema, provider_id: ctx.provider.id)

      assert Provider.list_active_staff_user_ids_for_program(unstaffed.id) == []
    end
  end

  defp user_ids(ctx) do
    ctx.program.id
    |> Provider.list_active_staff_user_ids_for_program()
    |> MapSet.new()
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
