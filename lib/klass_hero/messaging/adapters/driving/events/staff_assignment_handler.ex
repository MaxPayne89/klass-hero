defmodule KlassHero.Messaging.Adapters.Driving.Events.StaffAssignmentHandler do
  @moduledoc """
  Handles Provider integration events for staff assignment changes, at both the
  program and the session grain.

  On assignment, adds the staff user as a participant to every active program
  conversation where they are not already an active participant. The participant
  inserts and one `:participant_added` event per back-filled conversation are
  staged inside a single transaction, so the delivery job reaches the
  `ConversationSummaries` projection only after the rows it describes commit.

  On unassignment, delegates to `RemoveAssignedStaff` to soft-leave the staff in
  every active program conversation; the returned `:participant_removed` events
  are dispatched after the wrapping transaction commits.

  ## Both grains, one pair of paths (#784)

  A conversation is program-scoped, so entitlement to one is the **union** of the
  two staffing grains: on the program's roster, or overriding any one of its
  sessions. `Provider.list_conversation_staff_user_ids_for_program/1` is that
  union, and it is the only rule here — this module never re-derives it.

  Session events therefore need no paths of their own. Their payload is a superset
  of the program-level one, carrying the `program_id` the producer verified
  ownership against, so both grains land on the same add and remove functions.

  What the second grain does change is that a single retired row no longer settles
  removal, which is what the guard in `remove_staff_from_existing_conversations/2`
  is for.

  ## Why this handler survived #1321

  It used to maintain a second thing: `program_staff_participants`, a mirror of
  Provider's staffing. That mirror was deleted because it was *derivable* —
  Messaging now asks Provider directly. `conversation_participants` is not: the
  rows carry join/leave times and read receipts, facts that exist nowhere else.
  Derivable state gets read on demand; state with its own history stays
  event-maintained.

  A nil `staff_user_id` means the invite is unclaimed, so the event is skipped —
  there is no user to make a participant yet. This applies to **both**
  directions: nothing to add on assignment, nothing to tear down on
  unassignment. Skipping is not dropping: Provider replays the event on
  acceptance, once the user exists (#1312).
  """

  @behaviour KlassHero.Shared.ForHandlingEvents

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Domain.Events.MessagingEvents
  alias KlassHero.Messaging.RemoveAssignedStaff
  alias KlassHero.Shared.Adapters.Driven.Events.RetryHelpers
  alias KlassHero.Shared.Outbox

  require Logger

  @context Messaging

  # Program and session grain land on the same two paths: the session payload is a
  # superset of the program one (`Provider.Events.session_assignment_event/4`), so
  # nothing downstream has to know which grain produced the event. Derived lists
  # rather than four literals, so `subscribed_events/0` and the guard below cannot
  # drift apart — an event subscribed to but not guarded falls through to `:ignore`
  # and is silently dropped.
  @assignment_events [:staff_assigned_to_program, :staff_assigned_to_session]
  @unassignment_events [:staff_unassigned_from_program, :staff_unassigned_from_session]
  @handled_events @assignment_events ++ @unassignment_events

  @impl true
  def subscribed_events, do: @handled_events

  # One guard for every direction and grain, deliberately: when each clause carried
  # its own, only the assign side ever got one, and the unassign side compared a
  # column against nil for as long as nothing could reach it (#1309).
  @impl true
  def handle_event(%{event_type: event_type, payload: payload}) when event_type in @handled_events do
    if is_nil(Map.get(payload, :staff_user_id)) do
      Logger.debug("Skipping #{event_type} — staff member has no user_id yet",
        staff_member_id: payload.staff_member_id
      )

      :ok
    else
      with_retry(event_type, payload)
    end
  end

  def handle_event(_event), do: :ignore

  defp with_retry(event_type, payload) when event_type in @assignment_events do
    handle_assignment_with_retry(payload)
  end

  defp with_retry(event_type, payload) when event_type in @unassignment_events do
    handle_unassignment_with_retry(payload)
  end

  defp handle_assignment_with_retry(payload) do
    operation = fn ->
      add_staff_to_existing_conversations(payload.program_id, payload.staff_user_id)
    end

    context = %{
      operation_name: "handle staff assignment",
      aggregate_id: payload.staff_member_id,
      backoff_ms: 100
    }

    RetryHelpers.retry_and_normalize(operation, context)
  end

  defp handle_unassignment_with_retry(payload) do
    operation = fn ->
      remove_staff_from_existing_conversations(payload.program_id, payload.staff_user_id)
    end

    context = %{
      operation_name: "handle staff unassignment",
      aggregate_id: payload.staff_member_id,
      backoff_ms: 100
    }

    RetryHelpers.retry_and_normalize(operation, context)
  end

  # Participants and their events commit together.
  defp add_staff_to_existing_conversations(program_id, staff_user_id) do
    conversation_ids =
      KlassHero.Messaging.list_active_program_conversation_ids_without_participant(
        program_id,
        staff_user_id
      )

    case conversation_ids do
      [] ->
        :ok

      ids ->
        Outbox.transact(@context, fn -> backfill_participants(staff_user_id, ids) end)
    end
  end

  defp backfill_participants(staff_user_id, ids) do
    with {:ok, _count} <- KlassHero.Messaging.add_user_to_conversations(staff_user_id, ids) do
      events =
        Enum.map(ids, fn conversation_id ->
          MessagingEvents.participant_added(conversation_id, [staff_user_id], :later_assignment)
        end)

      {:ok, :ok, events}
    end
  end

  # Symmetric to add: RemoveAssignedStaff returns events as data.
  #
  # Guarded because entitlement is a union of two grains (#784), so retiring one
  # row does not settle the question. Without this, unassigning someone from the
  # *program* would evict them from conversations for a session they still run —
  # #784 reintroduced through the opposite door — and retiring one session override
  # would evict a member of the program roster.
  #
  # Safe to state as a plain re-read: delivery is post-commit, so the row this
  # event describes is already gone when the question is asked. The policy lives
  # here rather than in `RemoveAssignedStaff`, whose contract is the mechanical
  # "remove this user from every active conversation of this program".
  defp remove_staff_from_existing_conversations(program_id, staff_user_id) do
    if staff_user_id in Messaging.get_conversation_staff_user_ids(program_id) do
      Logger.debug("Keeping conversation membership — another staffing claim remains",
        program_id: program_id,
        user_id: staff_user_id
      )

      :ok
    else
      leave_all_conversations(program_id, staff_user_id)
    end
  end

  defp leave_all_conversations(program_id, staff_user_id) do
    Outbox.transact(@context, fn ->
      with {:ok, {_removals, events}} <- RemoveAssignedStaff.execute(program_id, staff_user_id) do
        {:ok, :ok, events}
      end
    end)
  end
end
