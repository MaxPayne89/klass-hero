defmodule KlassHero.Provider.StaffInviteAcceptMessagingTest do
  @moduledoc """
  End-to-end proof that accepting an invitation grants messaging access to
  programs assigned *before* the invite was claimed (#1312).

  A program assigned at invite time emits `staff_assigned_to_program` with a nil
  `staff_user_id`, which Messaging skips — and nothing re-announced when the user
  later appeared, so `program_staff_participants` stayed empty forever. Since
  that mirror is the only source of broadcast recipients, the staff member was
  cut out of every future broadcast, not just the historical ones.

  This starts at `Provider.accept_staff_invitation/2` and lets the real machinery
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

  alias KlassHero.Messaging.Participant
  alias KlassHero.Messaging.ProgramStaffParticipant
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

        # Nothing has consumed the events yet — the job is staged, not run.
        assert staff_participants(user.id) == []

        Oban.drain_queue(queue: :critical_events, with_recursion: true)
      end)
    end)

    assert [%ProgramStaffParticipant{active: true} = mirrored] = staff_participants(user.id)
    assert mirrored.program_id == program.id
    assert mirrored.provider_id == provider.id

    assert Repo.exists?(
             from(p in Participant,
               where: p.conversation_id == ^conversation.id and p.user_id == ^user.id and is_nil(p.left_at)
             )
           )
  end

  defp staff_participants(user_id) do
    Repo.all(from(p in ProgramStaffParticipant, where: p.staff_user_id == ^user_id))
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
