defmodule KlassHero.Participation.ParticipationEventHandler do
  @moduledoc """
  Integration event handler for Participation context.

  Listens to cross-context integration events and triggers Participation-owned
  data operations in response.

  ## Subscribed Events

  - `:child_data_anonymized` - Anonymizes session notes for the child:
    - Replaces note content with anonymized placeholder
    - Sets status to :rejected
    - Clears rejection reasons

  ## Error Handling

  Operations are handled with retry logic:
  - Transient errors → Retry once with backoff
  - Permanent errors → Log and return error
  """

  @behaviour KlassHero.Shared.ForHandlingEvents

  alias KlassHero.Participation
  alias KlassHero.Shared.Adapters.Driven.Events.RetryHelpers
  alias KlassHero.Shared.Domain.Events.Event

  @impl true
  def subscribed_events, do: [:child_data_anonymized, :program_created, :program_updated, :enrollment_created]

  @impl true
  def handle_event(%Event{event_type: :child_data_anonymized, entity_id: child_id}) do
    anonymize_notes_with_retry(child_id)
  end

  # Only the program id is taken from the payload: the schedule is re-read from
  # the owning context, so a lost broadcast can't leave sessions derived from a
  # stale snapshot. `program_updated` carries no diff, so this runs on every
  # program write and is a no-op when the schedule hasn't moved.
  def handle_event(%Event{event_type: type, entity_id: program_id}) when type in [:program_created, :program_updated] do
    case Participation.sync_sessions_for_program(program_id) do
      {:ok, _tally} -> :ok
      # A program without a full schedule simply has no sessions to derive.
      {:error, :incomplete_schedule} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def handle_event(%Event{event_type: :enrollment_created, payload: %{child_id: child_id, program_id: program_id}}) do
    Participation.backfill_roster_for_enrollment(child_id, program_id)
  end

  def handle_event(_event), do: :ignore

  defp anonymize_notes_with_retry(child_id) do
    operation = fn ->
      Participation.anonymize_session_notes_for_child(child_id)
    end

    context = %{
      operation_name: "anonymize session notes",
      # RetryHelpers API requires :aggregate_id — maps to entity_id in integration event context
      aggregate_id: child_id,
      backoff_ms: 100
    }

    RetryHelpers.retry_and_normalize(operation, context)
  end
end
