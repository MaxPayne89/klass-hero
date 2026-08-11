defmodule KlassHero.Messaging.Adapters.Driving.Events.StaffAssignmentHandler do
  @moduledoc """
  Handles Provider integration events for staff-program assignment changes.

  On assignment:
  1. Upserts the `program_staff_participants` projection (sets active=true).
  2. Adds the staff user as a participant to every active program conversation
     where they are not already an active participant. The participant inserts
     and one `:participant_added` event per back-filled conversation are staged
     inside a single transaction, so the delivery job reaches the
     `ConversationSummaries` projection only after the rows it describes commit.

  A nil `staff_user_id` means the invite is unclaimed, and the event is skipped
  rather than mirrored — there is no user to make a participant yet. This applies
  to **both** directions: an unclaimed staff member has nothing to mirror on
  assignment and nothing to tear down on unassignment, and the read side cannot
  express either as a query (`staff_user_id == nil` is not a comparison Ecto
  allows). Skipping the assignment is not a dropped assignment: Provider replays
  the event on acceptance, once the user exists (#1312).

  On unassignment:
  1. Deactivates the projection entry (sets active=false).
  2. Delegates to `RemoveAssignedStaff` to soft-leave the staff in every
     active program conversation; the returned `:participant_removed` events
     are dispatched after the wrapping transaction commits.
  """

  @behaviour KlassHero.Shared.ForHandlingEvents

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Domain.Events.MessagingEvents
  alias KlassHero.Messaging.RemoveAssignedStaff
  alias KlassHero.Messaging.StaffParticipants
  alias KlassHero.Shared.Adapters.Driven.Events.RetryHelpers
  alias KlassHero.Shared.Outbox

  require Logger

  @context Messaging

  @impl true
  def subscribed_events, do: [:staff_assigned_to_program, :staff_unassigned_from_program]

  # One guard for both directions, deliberately: when each clause carried its own,
  # only the assign side ever got one, and the unassign side compared a column
  # against nil for as long as nothing could reach it (#1309).
  @impl true
  def handle_event(%{event_type: event_type, payload: payload})
      when event_type in [:staff_assigned_to_program, :staff_unassigned_from_program] do
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

  defp with_retry(:staff_assigned_to_program, payload), do: handle_assignment_with_retry(payload)
  defp with_retry(:staff_unassigned_from_program, payload), do: handle_unassignment_with_retry(payload)

  defp handle_assignment_with_retry(payload) do
    operation = fn ->
      StaffParticipants.upsert_active(%{
        provider_id: payload.provider_id,
        program_id: payload.program_id,
        staff_user_id: payload.staff_user_id
      })

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
      StaffParticipants.deactivate(payload.program_id, payload.staff_user_id)
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
  defp remove_staff_from_existing_conversations(program_id, staff_user_id) do
    Outbox.transact(@context, fn ->
      with {:ok, {_removals, events}} <- RemoveAssignedStaff.execute(program_id, staff_user_id) do
        {:ok, :ok, events}
      end
    end)
  end
end
