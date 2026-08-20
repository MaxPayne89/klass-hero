defmodule KlassHero.Provider.StaffOffboardingCascadeTest do
  @moduledoc """
  End-to-end proof that offboarding a staff member actually removes them from the
  programs' conversations (#1292).

  The unit tests assert the events are staged. This one starts at
  `Provider.offboard_staff_member/1` and lets the real machinery run: staged
  events → Oban job → consumer registry → `Messaging.StaffAssignmentHandler`.

  It is the test the old code could not have passed. Removal was a bare
  `Repo.delete`, and `program_staff_assignments.staff_member_id` is
  `on_delete: :delete_all` — so Postgres destroyed the assignment rows, no
  changeset ran, nothing was staged, and the removed staff member stayed an
  active participant in every one of the program's conversations.
  """
  # async: false — swaps the :outbox adapter in application env, which every
  # other test reads (see outbox_test.exs for the same constraint).
  use KlassHero.DataCase, async: false

  import KlassHero.Factory

  alias KlassHero.Messaging
  alias KlassHero.Provider
  alias KlassHero.Shared.Adapters.Driven.Events.ObanOutbox

  test "offboarding removes the staff member from the program's conversations" do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    staff_user = KlassHero.AccountsFixtures.user_fixture()
    parent_user = KlassHero.AccountsFixtures.user_fixture()
    staff = insert(:staff_member_schema, provider_id: provider.id, user_id: staff_user.id)

    conversation =
      insert(:conversation_schema, provider_id: provider.id, type: "direct", program_id: program.id)

    insert(:participant_schema, conversation_id: conversation.id, user_id: parent_user.id)

    # The real outbox is swapped in around the act only. Doing it in `setup`
    # makes the fixtures above collide on providers_identity_id_index: with
    # ObanOutbox live, building a provider drives :user_registered through the
    # real handler, which creates a second profile for the same identity.
    with_real_outbox(fn ->
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _} =
          Provider.assign_staff_to_program(%{
            provider_id: provider.id,
            program_id: program.id,
            staff_member_id: staff.id
          })

        drain()

        # Precondition: assignment put them in the conversation, and Messaging
        # counts them as staff on the program.
        assert Messaging.participant?(conversation.id, staff_user.id)
        assert staff_user.id in Messaging.get_conversation_staff_user_ids(program.id)

        {:ok, %{unassigned_count: 1}} = Provider.offboard_staff_member(staff)

        # The two halves diverge here, which is the shape #1321 introduced.
        # "Counts as staff" is derived, so it flips with the write itself;
        # the participant row is event-maintained, so it survives until the
        # staged unassignment is consumed.
        refute staff_user.id in Messaging.get_conversation_staff_user_ids(program.id)
        assert Messaging.participant?(conversation.id, staff_user.id)

        drain()
      end)
    end)

    refute Messaging.participant?(conversation.id, staff_user.id)
  end

  defp drain, do: Oban.drain_queue(queue: :events, with_recursion: true)

  defp with_real_outbox(fun) do
    original = Application.get_env(:klass_hero, :outbox)
    Application.put_env(:klass_hero, :outbox, module: ObanOutbox)

    try do
      fun.()
    after
      Application.put_env(:klass_hero, :outbox, original)
    end
  end
end
