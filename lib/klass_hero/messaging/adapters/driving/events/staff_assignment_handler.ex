defmodule KlassHero.Messaging.Adapters.Driving.Events.StaffAssignmentHandler do
  @moduledoc """
  Handles Provider integration events for staff-program assignment changes.

  On assignment:
  1. Upserts the `program_staff_participants` projection (sets active=true).
  2. Adds the staff user as a participant to every active program conversation
     where they are not already an active participant. The participant inserts
     and one `:participant_added` domain event per back-filled conversation
     are collected inside a single `Repo.transaction`; events dispatch
     *after* the transaction commits so the `ConversationSummaries` projection
     can read-your-own-writes on a separate DB connection.

  On unassignment:
  1. Deactivates the projection entry (sets active=false).
  2. Delegates to `RemoveAssignedStaff` to soft-leave the staff in every
     active program conversation; the returned `:participant_removed` events
     are dispatched after the wrapping transaction commits.
  """

  @behaviour KlassHero.Shared.ForHandlingEvents

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ProgramStaffParticipantRepository
  alias KlassHero.Messaging.Domain.Events.MessagingEvents
  alias KlassHero.Messaging.RemoveAssignedStaff
  alias KlassHero.Shared.Adapters.Driven.Events.RetryHelpers
  alias KlassHero.Shared.Outbox

  require Logger

  @context Messaging

  @impl true
  def subscribed_events, do: [:staff_assigned_to_program, :staff_unassigned_from_program]

  @impl true
  def handle_event(%{event_type: :staff_assigned_to_program, payload: payload}) do
    staff_user_id = Map.get(payload, :staff_user_id)

    if is_nil(staff_user_id) do
      Logger.debug("Skipping staff assignment — no user_id yet",
        staff_member_id: payload.staff_member_id
      )

      :ok
    else
      handle_assignment_with_retry(payload)
    end
  end

  def handle_event(%{event_type: :staff_unassigned_from_program, payload: payload}) do
    handle_unassignment_with_retry(payload)
  end

  def handle_event(_event), do: :ignore

  defp handle_assignment_with_retry(payload) do
    operation = fn ->
      ProgramStaffParticipantRepository.upsert_active(%{
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
      ProgramStaffParticipantRepository.deactivate(payload.program_id, payload.staff_user_id)
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
