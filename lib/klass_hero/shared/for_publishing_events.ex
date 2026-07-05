defmodule KlassHero.Shared.ForPublishingEvents do
  @moduledoc """
  Port (interface) for publishing domain events.

  This behaviour defines the contract for event publishing, allowing
  different implementations (PubSub, Kafka, test mocks, etc.).

  ## Topic Naming Convention

  Topics follow the pattern: `{aggregate_type}:{event_type}`

  Examples:
  - `user:registered`
  - `enrollment:confirmed`
  - `program:updated`

  ## Implementation

  Implementations must handle:
  1. Topic derivation from event properties
  2. Event serialization (if needed)
  3. Delivery to subscribers
  4. Error handling and logging
  """

  alias KlassHero.Shared.Domain.Events.DomainEvent

  @type topic :: String.t()
  @type publish_result :: :ok | {:error, term()}

  @doc """
  Publishes a domain event to the appropriate topic.

  The implementation determines the topic based on the event's
  aggregate_type and event_type.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @callback publish(DomainEvent.t()) :: publish_result()

  @doc """
  Publishes a domain event to a specific topic.

  Use this when you need to override the default topic derivation.
  """
  @callback publish(DomainEvent.t(), topic()) :: publish_result()

  @doc """
  Publishes multiple events atomically (if supported by implementation).

  Returns `:ok` if all events were published successfully.
  For non-atomic implementations, events are published sequentially
  and the first error is returned.
  """
  @callback publish_all([DomainEvent.t()]) :: publish_result()
end
