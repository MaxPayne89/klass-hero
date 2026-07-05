defmodule KlassHero.ProgramCatalog.Adapters.Driving.Events.EnrollmentEventHandler do
  @moduledoc """
  Integration event handler for the ProgramCatalog context.

  Listens to enrollment-related events and reacts accordingly:

  ## Subscribed Events

  - `:participant_policy_set` - Acknowledged; ready for future search indexing
    when programs become filterable by eligibility criteria.
  """

  @behaviour KlassHero.Shared.ForHandlingEvents

  require Logger

  @impl true
  def subscribed_events, do: [:participant_policy_set]

  @impl true
  def handle_event(%{event_type: :participant_policy_set} = event) do
    # No-op for now; placeholder for future search index updates (filter programs by eligibility criteria).
    Logger.debug("[EnrollmentEventHandler] Received participant_policy_set",
      program_id: event.entity_id
    )

    :ok
  end

  def handle_event(_event), do: :ignore
end
