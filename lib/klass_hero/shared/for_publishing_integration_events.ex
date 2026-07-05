defmodule KlassHero.Shared.ForPublishingIntegrationEvents do
  @moduledoc """
  Port (interface) for publishing integration events across bounded contexts.

  This behaviour defines the contract for integration event publishing,
  separate from domain event publishing. Integration events cross context
  boundaries with a stable, versioned contract.

  ## Topic Naming Convention

  Topics follow the pattern: `integration:{source_context}:{event_type}`

  Examples:
  - `integration:identity:child_data_anonymized`
  - `integration:enrollment:enrollment_confirmed`

  ## Implementation

  Implementations must handle:
  1. Topic derivation from event properties
  2. Event serialization (if needed)
  3. Delivery to subscribers
  4. Error handling and logging
  """

  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @type topic :: String.t()
  @type publish_result :: :ok | {:error, term()}

  @doc """
  Publishes an integration event to the appropriate topic.

  The implementation determines the topic based on the event's
  source_context and event_type.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @callback publish(IntegrationEvent.t()) :: publish_result()

  @doc """
  Publishes an integration event to a specific topic.

  Use this when you need to override the default topic derivation.
  """
  @callback publish(IntegrationEvent.t(), topic()) :: publish_result()

  @doc """
  Publishes multiple integration events sequentially.

  Returns `:ok` if all events were published successfully.
  The first error encountered is returned.
  """
  @callback publish_all([IntegrationEvent.t()]) :: publish_result()
end
