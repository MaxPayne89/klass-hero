defmodule KlassHero.Shared.Domain.Events.IntegrationEvent do
  @moduledoc """
  Base structure for cross-context integration events.

  Integration events are the public contract between bounded contexts. Unlike
  domain events (internal to a context), integration events:

  - Use `source_context` to identify the publishing bounded context
  - Use `entity_type`/`entity_id` instead of `aggregate_type`/`aggregate_id`
  - Carry a `version` field for schema evolution and forward compatibility
  - Contain only primitive types in `payload` for a stable cross-context contract

  ## Topic Naming Convention

  Integration event topics follow: `integration:{source_context}:{event_type}`

  Examples:
  - `integration:identity:child_data_anonymized`
  - `integration:enrollment:enrollment_confirmed`

  ## Message Format

  Subscribers receive: `{:integration_event, %IntegrationEvent{}}`

  ## Event Criticality

  Events can be marked with a criticality level via metadata:
  - `:critical` - Must not be lost (durable delivery via CriticalEventDispatcher + Oban)
  - `:normal` - Standard fire-and-forget (default)
  """

  alias KlassHero.Shared.Domain.Events.EventMetadata

  @type criticality :: :critical | :normal

  @type t :: %__MODULE__{
          event_id: String.t(),
          event_type: atom(),
          source_context: atom(),
          entity_type: atom(),
          entity_id: String.t() | integer(),
          occurred_at: DateTime.t(),
          payload: map(),
          metadata: map(),
          version: pos_integer()
        }

  @enforce_keys [
    :event_id,
    :event_type,
    :source_context,
    :entity_type,
    :entity_id,
    :occurred_at,
    :payload
  ]
  defstruct [
    :event_id,
    :event_type,
    :source_context,
    :entity_type,
    :entity_id,
    :occurred_at,
    :payload,
    metadata: %{},
    version: 1
  ]

  @doc """
  Creates a new integration event with auto-generated ID and timestamp.

  ## Parameters

  - `event_type` - Atom identifying the event (e.g., `:child_data_anonymized`)
  - `source_context` - Atom identifying the producing context (e.g., `:identity`)
  - `entity_type` - Public-facing entity name (e.g., `:child`)
  - `entity_id` - Public-facing entity ID
  - `payload` - Event data map (primitive types only for stable contract)
  - `opts` - Metadata options

  ## Options

  - `:criticality` - Event criticality level (:critical or :normal, default: :normal)
  - `:correlation_id` - ID to correlate related events
  - `:causation_id` - ID of the event that caused this event
  - `:version` - Schema version (default: 1)

  ## Examples

      iex> event = IntegrationEvent.new(:child_data_anonymized, :identity, :child, "uuid", %{child_id: "uuid"})
      iex> event.event_type
      :child_data_anonymized
      iex> event.source_context
      :identity

      iex> event = IntegrationEvent.new(:child_data_anonymized, :identity, :child, "uuid", %{}, criticality: :critical)
      iex> IntegrationEvent.critical?(event)
      true
  """
  @spec new(atom(), atom(), atom(), String.t() | integer(), map(), keyword()) :: t()
  def new(event_type, source_context, entity_type, entity_id, payload, opts \\ []) do
    metadata = EventMetadata.build_metadata(opts)
    version = Keyword.get(opts, :version, 1)
    EventMetadata.validate_critical_payload!(metadata.criticality, payload)

    %__MODULE__{
      event_id: EventMetadata.generate_event_id(),
      event_type: event_type,
      source_context: source_context,
      entity_type: entity_type,
      entity_id: entity_id,
      occurred_at: DateTime.utc_now(),
      payload: payload,
      metadata: metadata,
      version: version
    }
  end

  @doc """
  The event's topic: `integration:{source_context}:{event_type}`.

  A pure function of two fields, so it lives here rather than on any one of the
  things that need it — the outbox asking "does anyone consume this?", the
  delivery job asking "who?", and the publisher asking "where do I broadcast?"
  must all derive the same string, and the surest way is one function.
  """
  @spec topic(t()) :: String.t()
  def topic(%__MODULE__{source_context: source_context, event_type: event_type}) do
    "integration:#{source_context}:#{event_type}"
  end

  @doc """
  Returns the criticality level of the event (defaults to :normal).
  """
  @spec criticality(t()) :: criticality()
  defdelegate criticality(event), to: EventMetadata

  @doc """
  Returns true if this is a critical event.
  """
  @spec critical?(t()) :: boolean()
  defdelegate critical?(event), to: EventMetadata

  @doc """
  Returns the correlation_id from metadata if present.
  """
  @spec correlation_id(t()) :: String.t() | nil
  defdelegate correlation_id(event), to: EventMetadata

  @doc """
  Returns the causation_id from metadata if present.
  """
  @spec causation_id(t()) :: String.t() | nil
  defdelegate causation_id(event), to: EventMetadata
end
