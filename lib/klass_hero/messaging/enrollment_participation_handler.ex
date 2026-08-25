defmodule KlassHero.Messaging.EnrollmentParticipationHandler do
  @moduledoc """
  Handles Enrollment's `:enrollment_created` event by adding the newly enrolled
  parent to their program's broadcast conversation.

  `BroadcastToProgram` adds participants from the enrollee list *as it stands when the
  broadcast is sent*. Nothing maintained that membership afterwards, so a family who
  enrolled between two broadcasts was not a participant, and `verify_participant/2`
  hid the thread from them entirely (#381). This handler is the missing half: the
  add path for parents, mirroring `StaffAssignmentHandler`'s for staff.

  ## Broadcasts only

  Unlike the staff path this must **not** use
  `list_active_program_conversation_ids_without_participant/2`. A `:direct`
  parent↔provider conversation also carries a `program_id`, so the program-wide list
  would seat a new family in every other family's private thread. Staff legitimately
  belong in both kinds; parents belong only in the broadcast.

  ## Read state at join

  Nothing to do here: `add_user_to_conversations/2` seats everyone with their cursor
  at whatever the conversation already held, so the history stays readable while the
  unread badge starts at zero. Joining late should not arrive as twenty
  notifications — and that rule belongs to seating, not to this one caller.

  ## A nil parent_user_id is skipped, not dropped

  `Enrollment.do_create_enrollment/2` resolves the parent's user id late, and a parent
  profile with no user behind it yields `nil`. `conversation_participants.user_id` is
  `NOT NULL` with an FK, so an unguarded insert *raises* — and `RetryHelpers` only
  classifies returned error tuples, so a raise skips the backoff path and rides Oban's
  attempts straight to a discard. Unlike #1312's unclaimed staff invite there is no
  later claim to replay: the invite claim is what creates the parent, so by the time
  `InviteFamilyReadyHandler` enrolls them the user already exists. A `nil` here means a
  genuinely orphaned parent row, not a pending one.
  """

  @behaviour KlassHero.Shared.ForHandlingEvents

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Events
  alias KlassHero.Shared.Adapters.Driven.Events.RetryHelpers
  alias KlassHero.Shared.Outbox

  require Logger

  @context Messaging

  @impl true
  def subscribed_events, do: [:enrollment_created]

  @impl true
  def handle_event(%{event_type: :enrollment_created, payload: payload}) do
    case Map.get(payload, :parent_user_id) do
      nil ->
        Logger.debug("Skipping enrollment_created — enrollment has no parent user",
          program_id: Map.get(payload, :program_id),
          enrollment_id: Map.get(payload, :enrollment_id)
        )

        :ok

      parent_user_id ->
        with_retry(payload.program_id, parent_user_id, Map.get(payload, :enrollment_id))
    end
  end

  def handle_event(_event), do: :ignore

  defp with_retry(program_id, parent_user_id, enrollment_id) do
    operation = fn -> add_parent_to_broadcast(program_id, parent_user_id) end

    context = %{
      operation_name: "handle enrollment participation",
      aggregate_id: enrollment_id,
      backoff_ms: 100
    }

    RetryHelpers.retry_and_normalize(operation, context)
  end

  # Participants and their events commit together, so the delivery job reaches
  # ConversationSummaries only after the rows it describes exist.
  defp add_parent_to_broadcast(program_id, parent_user_id) do
    case Messaging.list_active_broadcast_ids_without_participant(program_id, parent_user_id) do
      [] ->
        :ok

      ids ->
        Outbox.transact(@context, fn -> backfill_participants(parent_user_id, ids) end)
    end
  end

  defp backfill_participants(parent_user_id, ids) do
    with {:ok, _count} <- Messaging.add_user_to_conversations(parent_user_id, ids) do
      events =
        Enum.map(ids, fn conversation_id ->
          Events.participant_added(conversation_id, [parent_user_id], :later_enrollment)
        end)

      {:ok, :ok, events}
    end
  end
end
