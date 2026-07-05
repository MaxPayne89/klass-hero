defmodule KlassHero.Participation.Adapters.Driving.Events.ParticipationEventHandler do
  @moduledoc """
  Integration event handler for Participation context.

  Listens to cross-context integration events and triggers Participation-owned
  data operations in response.

  ## Subscribed Events

  - `:child_data_anonymized` - Anonymizes behavioral notes for the child:
    - Replaces note content with anonymized placeholder
    - Sets status to :rejected
    - Clears rejection reasons

  ## Error Handling

  Operations are handled with retry logic:
  - Transient errors → Retry once with backoff
  - Permanent errors → Log and return error
  """

  @behaviour KlassHero.Shared.ForHandlingIntegrationEvents

  alias KlassHero.Participation
  alias KlassHero.Shared.Adapters.Driven.Events.RetryHelpers
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @impl true
  def subscribed_events, do: [:child_data_anonymized]

  @impl true
  def handle_event(%IntegrationEvent{event_type: :child_data_anonymized, entity_id: child_id}) do
    anonymize_notes_with_retry(child_id)
  end

  def handle_event(_event), do: :ignore

  defp anonymize_notes_with_retry(child_id) do
    operation = fn ->
      Participation.anonymize_behavioral_notes_for_child(child_id)
    end

    context = %{
      operation_name: "anonymize behavioral notes",
      # RetryHelpers API requires :aggregate_id — maps to entity_id in integration event context
      aggregate_id: child_id,
      backoff_ms: 100
    }

    RetryHelpers.retry_and_normalize(operation, context)
  end
end
