defmodule KlassHero.Provider.StaffInviteAcceptMessagingTest do
  @moduledoc """
  End-to-end proof that accepting an invitation grants messaging access to
  programs assigned *before* the invite was claimed (#1312).

  A program assigned at invite time emits `staff_assigned_to_program` with a nil
  `staff_user_id`, which Messaging skips — and nothing re-announced when the user
  later appeared.

  #1321 split that bug in half, and the two halves now behave differently:

    * **Who counts as staff** is derived from Provider, so it is true the moment
      `user_id` is set — no event, no job. This half can no longer regress.
    * **Conversation participants** are still event-maintained, because the rows
      carry join/leave and read receipts. The skipped announcement means no row
      was ever created, and only the acceptance replay creates it.

  So this test asserts the derived read *before* draining the queue and the
  participant row *after* — the asymmetry is the point.

  It starts at `Provider.accept_staff_invitation/2` and lets the real machinery
  run: staged events → Oban job → consumer registry → `StaffAssignmentHandler`.
  The unit tests assert what was staged; only this one proves it lands.
  """
  # async: false — swaps the :outbox adapter in application env, which every
  # other test reads (see outbox_test.exs for the same constraint).
  use KlassHero.DataCase, async: false

  import Ecto.Query
  import KlassHero.AccountsFixtures
  import KlassHero.Factory
  import KlassHero.ProviderFixtures

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Participant
  alias KlassHero.Provider
  alias KlassHero.Shared.Adapters.Driven.Events.ObanOutbox

  test "accepting an invitation backfills messaging for a program assigned before the claim" do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    user = user_fixture()

    # Invited, not yet claimed: user_id is nil, so the assignment below announces
    # a nil staff_user_id and Messaging skips it.
    staff =
      staff_member_fixture(%{
        provider_id: provider.id,
        email: "invited-#{System.unique_integer([:positive])}@example.com",
        invitation_status: :sent,
        invitation_token_hash: :crypto.hash(:sha256, "tok-#{System.unique_integer([:positive])}"),
        invitation_sent_at: DateTime.utc_now()
      })

    assert is_nil(staff.user_id)

    insert(:program_staff_assignment_schema,
      provider_id: provider.id,
      program_id: program.id,
      staff_member_id: staff.id
    )

    # A broadcast that already exists — the history the staff member is missing.
    conversation =
      insert(:conversation_schema,
        provider_id: provider.id,
        program_id: program.id,
        type: :program_broadcast
      )

    with_real_outbox(fn ->
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, accepted} = Provider.accept_staff_invitation(staff, user.id)
        assert accepted.user_id == user.id

        # Derived, so already true: no event has been consumed yet — the job is
        # staged, not run — and Messaging nonetheless counts them as staff.
        assert Messaging.get_active_staff_user_ids(program.id) == [user.id]

        # The participant row is the half that still needs the replay to land.
        refute participant?(conversation.id, user.id)

        Oban.drain_queue(queue: :events, with_recursion: true)
      end)
    end)

    assert participant?(conversation.id, user.id)
  end

  defp participant?(conversation_id, user_id) do
    Repo.exists?(
      from(p in Participant,
        where: p.conversation_id == ^conversation_id and p.user_id == ^user_id and is_nil(p.left_at)
      )
    )
  end

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
