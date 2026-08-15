defmodule KlassHero.Shared.Domain.Events.Event do
  @moduledoc """
  Base structure for cross-context integration events.

  Integration events are the public contract between bounded contexts. Unlike
  domain events (internal to a context), integration events:

  - Use `source_context` to identify the publishing bounded context
  - Use `entity_type`/`entity_id` instead of `aggregate_type`/`aggregate_id`
  - Carry a `payload` of JSON scalars, plus atoms and `Date`/`Time`/`DateTime`/
    `NaiveDateTime`/`Decimal`, which `EventSerializer` round-trips with their
    types intact (#1311, #1317). Anything else loses its type in `oban_jobs.args`, so
    `PayloadGuard.validate_payload!/1` rejects it at construction —
    `PayloadCodec` is the one list of what survives.

  The envelope carries only what something writes. A `metadata` map (`correlation_id`,
  `causation_id`, W3C trace headers) and a `version` field were both retired in #1358:
  no producer ever set either, nothing branched on them, and trace context propagates
  through `oban_jobs.args`, not per-event metadata. Re-add `version` when a payload
  contract actually needs to evolve — a row written without it deserializes fine, the
  same way one written before `payload_types` existed does.

  ## Topic Naming Convention

  Integration event topics follow: `integration:{source_context}:{event_type}`

  Examples:
  - `integration:identity:child_data_anonymized`
  - `integration:enrollment:enrollment_confirmed`

  ## Message Format

  Subscribers receive: `{:integration_event, %Event{}}`

  ## Delivery is not a per-event choice

  Every staged event takes the same durable Outbox → Oban → `EventDeliveryWorker`
  route. Events used to carry a criticality level that was meant to select between
  durable and fire-and-forget delivery; ADR-0014 collapsed the two tiers into one,
  and #1326 removed the field. Being in `EventConsumerRegistry` is the only
  condition that decides anything.
  """

  alias KlassHero.Shared.Domain.Events.PayloadGuard

  @type t :: %__MODULE__{
          event_id: String.t(),
          event_type: atom(),
          source_context: atom(),
          entity_type: atom(),
          entity_id: String.t() | integer(),
          occurred_at: DateTime.t(),
          payload: map()
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
    :payload
  ]

  @doc """
  Creates a new integration event with auto-generated ID and timestamp.

  ## Parameters

  - `event_type` - Atom identifying the event (e.g., `:child_data_anonymized`)
  - `source_context` - Atom identifying the producing context (e.g., `:identity`)
  - `entity_type` - Public-facing entity name (e.g., `:child`)
  - `entity_id` - Public-facing entity ID
  - `payload` - Event data map (primitive types only for stable contract)

  ## Examples

      iex> event = Event.new(:child_data_anonymized, :identity, :child, "uuid", %{child_id: "uuid"})
      iex> event.event_type
      :child_data_anonymized
      iex> event.source_context
      :identity
  """
  @spec new(atom(), atom(), atom(), String.t() | integer(), map()) :: t()
  def new(event_type, source_context, entity_type, entity_id, payload) do
    PayloadGuard.validate_payload!(payload)

    %__MODULE__{
      event_id: Ecto.UUID.generate(),
      event_type: event_type,
      source_context: source_context,
      entity_type: entity_type,
      entity_id: entity_id,
      occurred_at: DateTime.utc_now(),
      payload: payload
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
end
