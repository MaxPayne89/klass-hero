defmodule KlassHero.Provider.Assignments.ListConversationStaffUserIdsForProgramTest do
  @moduledoc """
  Who may participate in a program's *conversations* (#784).

  Deliberately wider than `list_active_staff_user_ids_for_program/1`: a session
  override admits someone who holds no program assignment at all
  (`assign_staff_to_session/1` requires only active employment), and messaging is
  program-scoped, so running any one session earns the whole program's thread.

  The union is *not* the resolution `get_session_staffing/1` performs. That one
  replaces the program roster with a session's overrides, because attendance asks
  about one session. This one adds to it, because a conversation spans them all.
  """
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider
  alias KlassHero.Provider.SessionStaffAssignment
  alias KlassHero.Repo

  # One fixture carrying every rule at once, so a regression in any single rule
  # shows as a diff on one id set rather than passing quietly elsewhere.
  setup do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    session = insert(:program_session_schema, program_id: program.id)

    on_program = claimed_staff(provider.id)
    on_session = claimed_staff(provider.id)
    on_both = claimed_staff(provider.id)
    released_from_session = claimed_staff(provider.id)
    deactivated = claimed_staff(provider.id)
    unclaimed = insert(:staff_member_schema, provider_id: provider.id, user_id: nil)

    other_program = insert(:program_schema, provider_id: provider.id)
    other_session = insert(:program_session_schema, program_id: other_program.id)
    elsewhere = claimed_staff(provider.id)

    assign_to_program!(provider.id, program.id, on_program.id)
    assign_to_program!(provider.id, program.id, on_both.id)

    for staff <- [on_session, on_both, deactivated, unclaimed] do
      override!(provider.id, session.id, staff.id)
    end

    override!(provider.id, other_session.id, elsewhere.id)

    provider.id
    |> override!(session.id, released_from_session.id)
    |> SessionStaffAssignment.unassign_changeset()
    |> Repo.update!()

    {:ok, deactivated} = Provider.deactivate_staff_member(deactivated)

    %{
      provider: provider,
      program: program,
      on_program: on_program,
      on_session: on_session,
      on_both: on_both,
      released_from_session: released_from_session,
      deactivated: deactivated,
      unclaimed: unclaimed,
      elsewhere: elsewhere
    }
  end

  describe "list_conversation_staff_user_ids_for_program/1" do
    test "includes staff assigned to the program", ctx do
      assert MapSet.member?(user_ids(ctx), ctx.on_program.user_id)
    end

    test "includes staff who only override one of the program's sessions", ctx do
      assert MapSet.member?(user_ids(ctx), ctx.on_session.user_id)
    end

    test "returns someone holding both claims exactly once", ctx do
      ids = Provider.list_conversation_staff_user_ids_for_program(ctx.program.id)

      assert Enum.count(ids, &(&1 == ctx.on_both.user_id)) == 1
    end

    for {label, key} <- [
          {"an override that was retired", :released_from_session},
          {"a deactivated staff member", :deactivated},
          {"unclaimed staff, who have no user id (#1309)", :unclaimed},
          {"an override on another program's session", :elsewhere}
        ] do
      test "excludes #{label}", ctx do
        excluded = ctx[unquote(key)]

        refute MapSet.member?(user_ids(ctx), excluded.user_id),
               "expected #{unquote(label)} (user_id #{inspect(excluded.user_id)}) to be excluded"
      end
    end

    test "returns an empty list for a program nobody staffs at either grain", ctx do
      unstaffed = insert(:program_schema, provider_id: ctx.provider.id)

      assert Provider.list_conversation_staff_user_ids_for_program(unstaffed.id) == []
    end
  end

  defp user_ids(ctx) do
    ctx.program.id
    |> Provider.list_conversation_staff_user_ids_for_program()
    |> MapSet.new()
  end

  defp claimed_staff(provider_id) do
    insert(:staff_member_schema,
      provider_id: provider_id,
      user_id: AccountsFixtures.user_fixture().id,
      invitation_status: :accepted
    )
  end

  defp assign_to_program!(provider_id, program_id, staff_member_id) do
    {:ok, assignment} =
      Provider.assign_staff_to_program(%{
        provider_id: provider_id,
        program_id: program_id,
        staff_member_id: staff_member_id
      })

    assignment
  end

  # Inserted rather than driven through `assign_staff_to_session/1`: that command
  # has its own test, and this one is about the read.
  defp override!(provider_id, session_id, staff_member_id) do
    insert(:session_staff_assignment_schema,
      provider_id: provider_id,
      session_id: session_id,
      staff_member_id: staff_member_id
    )
  end
end
