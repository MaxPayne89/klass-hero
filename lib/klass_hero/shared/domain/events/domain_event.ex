defmodule KlassHero.Shared.Domain.Events.DomainEvent do
  @moduledoc """
  Base structure for all domain events across bounded contexts.

  All domain events include:
  - `event_id`: Unique identifier for this event instance (UUID)
  - `event_type`: Atom identifying the event type (e.g., :user_registered)
  - `aggregate_id`: ID of the entity that generated the event
  - `aggregate_type`: Type of entity (e.g., :user, :program, :enrollment)
  - `occurred_at`: UTC timestamp when the event occurred
  - `payload`: Event-specific data as a map
  - `metadata`: Optional context (correlation_id, causation_id, user_id, criticality)

  ## Event Criticality

  Events can be marked with a criticality level via metadata:
  - `:critical` - Must not be lost (durable delivery via CriticalEventDispatcher + Oban)
  - `:normal` - Standard fire-and-forget (default)

  ## Payload Constraint (critical events)

  `:critical` event payloads are serialized to Oban's jsonb `args` for durable
  delivery, so their values must be JSON scalars (string/number/boolean/nil),
  nested freely in maps and lists. A `DateTime`, atom, or tuple value silently
  loses its type across the round trip (see #1010); `new/5` raises on such
  payloads. Encode timestamps as ISO8601 strings and enums as strings.
  """

  alias KlassHero.Shared.Domain.Events.EventMetadata

  @type criticality :: :critical | :normal

  @type t :: %__MODULE__{
          event_id: String.t(),
          event_type: atom(),
          aggregate_id: String.t() | integer(),
          aggregate_type: atom(),
          occurred_at: DateTime.t(),
          payload: map(),
          metadata: map()
        }

  @enforce_keys [:event_id, :event_type, :aggregate_id, :aggregate_type, :occurred_at, :payload]
  defstruct [
    :event_id,
    :event_type,
    :aggregate_id,
    :aggregate_type,
    :occurred_at,
    :payload,
    metadata: %{}
  ]

  @doc """
  Creates a new domain event with auto-generated ID and timestamp.

  ## Options
  - `:criticality` - Event criticality level (:critical or :normal, default: :normal)
  - `:correlation_id` - ID to correlate related events
  - `:causation_id` - ID of the event that caused this event
  - `:user_id` - ID of the user who triggered the action

  ## Examples

      iex> event = DomainEvent.new(:user_registered, 123, :user, %{email: "test@example.com"})
      iex> event.event_type
      :user_registered
      iex> event.aggregate_id
      123

      iex> event = DomainEvent.new(:order_placed, "uuid", :order, %{total: 100}, criticality: :critical)
      iex> DomainEvent.critical?(event)
      true
  """
  @spec new(atom(), String.t() | integer(), atom(), map(), keyword()) :: t()
  def new(event_type, aggregate_id, aggregate_type, payload, opts \\ []) do
    # DomainEvent includes :user_id in metadata (unlike IntegrationEvent) for audit/tracing.
    metadata = EventMetadata.build_metadata(opts, [:user_id])
    EventMetadata.validate_critical_payload!(metadata.criticality, payload)

    %__MODULE__{
      event_id: EventMetadata.generate_event_id(),
      event_type: event_type,
      aggregate_id: aggregate_id,
      aggregate_type: aggregate_type,
      occurred_at: DateTime.utc_now(),
      payload: payload,
      metadata: metadata
    }
  end

  @spec criticality(t()) :: criticality()
  defdelegate criticality(event), to: EventMetadata

  @spec critical?(t()) :: boolean()
  defdelegate critical?(event), to: EventMetadata

  @spec correlation_id(t()) :: String.t() | nil
  defdelegate correlation_id(event), to: EventMetadata

  @spec causation_id(t()) :: String.t() | nil
  defdelegate causation_id(event), to: EventMetadata
end
