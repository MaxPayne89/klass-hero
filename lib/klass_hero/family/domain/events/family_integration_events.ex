defmodule KlassHero.Family.Domain.Events.FamilyIntegrationEvents do
  @moduledoc """
  Factory module for creating Family context integration events.

  Integration events are the public contract between bounded contexts.
  They carry stable, versioned payloads with only primitive types.

  ## Events

  - `:child_created` - Emitted when a new child record is created. Downstream
    contexts (e.g. Messaging) react to maintain local child name lookups.
    Topic: `integration:family:child_created`
  - `:child_updated` - Emitted when an existing child record is updated.
    Downstream contexts (e.g. Messaging) react to refresh local child name lookups.
    Topic: `integration:family:child_updated`
  - `:child_data_anonymized` - Emitted when a child's PII is anonymized during
    GDPR account deletion (critical). Downstream contexts (e.g. Participation)
    react to this event to anonymize their own child-related data.
  - `:invite_family_ready` - Emitted after creating parent + child from an
    invite claim. Downstream contexts (e.g. Enrollment) react to auto-enroll
    the child. Topic: `integration:family:invite_family_ready`
  """

  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @typedoc "Payload for `:child_created` events."
  @type child_created_payload :: %{
          required(:child_id) => String.t(),
          optional(:parent_id) => String.t(),
          optional(:first_name) => String.t(),
          optional(:last_name) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:child_updated` events."
  @type child_updated_payload :: %{
          required(:child_id) => String.t(),
          optional(:first_name) => String.t(),
          optional(:last_name) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:child_data_anonymized` events."
  @type child_data_anonymized_payload :: %{
          required(:child_id) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:invite_family_ready` events."
  @type invite_family_ready_payload :: %{
          required(:invite_id) => String.t(),
          optional(atom()) => term()
        }

  @source_context :family
  @entity_type :child

  @doc """
  Creates a `child_created` integration event.

  Emitted when a new child record is created. Published on topic
  `integration:family:child_created`.

  ## Parameters

  - `child_id` - The ID of the newly created child
  - `payload` - Event-specific data (child_id, parent_id, first_name, last_name)
  - `opts` - Metadata options (correlation_id, causation_id)

  ## Raises

  - `ArgumentError` if `child_id` is nil or empty

  ## Examples

      iex> event = FamilyIntegrationEvents.child_created("child-uuid", %{first_name: "Emma"})
      iex> event.event_type
      :child_created
      iex> event.source_context
      :family
      iex> event.entity_type
      :child
  """
  def child_created(child_id, payload \\ %{}, opts \\ [])

  def child_created(child_id, payload, opts) when is_binary(child_id) and byte_size(child_id) > 0 do
    base_payload = %{child_id: child_id}

    IntegrationEvent.new(
      :child_created,
      @source_context,
      @entity_type,
      child_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def child_created(child_id, _payload, _opts) do
    raise ArgumentError,
          "child_created/3 requires a non-empty child_id string, got: #{inspect(child_id)}"
  end

  @doc """
  Creates a `child_updated` integration event.

  Emitted when an existing child record is updated. Published on topic
  `integration:family:child_updated`.

  ## Parameters

  - `child_id` - The ID of the updated child
  - `payload` - Event-specific data (child_id, first_name, last_name)
  - `opts` - Metadata options (correlation_id, causation_id)

  ## Raises

  - `ArgumentError` if `child_id` is nil or empty

  ## Examples

      iex> event = FamilyIntegrationEvents.child_updated("child-uuid", %{first_name: "Emily"})
      iex> event.event_type
      :child_updated
      iex> event.source_context
      :family
      iex> event.entity_type
      :child
  """
  def child_updated(child_id, payload \\ %{}, opts \\ [])

  def child_updated(child_id, payload, opts) when is_binary(child_id) and byte_size(child_id) > 0 do
    base_payload = %{child_id: child_id}

    IntegrationEvent.new(
      :child_updated,
      @source_context,
      @entity_type,
      child_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def child_updated(child_id, _payload, _opts) do
    raise ArgumentError,
          "child_updated/3 requires a non-empty child_id string, got: #{inspect(child_id)}"
  end

  @doc """
  Creates a `child_data_anonymized` integration event.

  This event is marked as `:critical` by default since it is part of the
  GDPR deletion cascade and must not be lost.

  ## Parameters

  - `child_id` - The ID of the child whose data was anonymized
  - `payload` - Additional event-specific data
  - `opts` - Metadata options (correlation_id, causation_id)

  ## Payload Fields

  Standard payload includes:
  - `child_id` - The child's ID

  ## Raises

  - `ArgumentError` if `child_id` is nil or empty

  ## Examples

      iex> event = FamilyIntegrationEvents.child_data_anonymized("child-uuid")
      iex> event.event_type
      :child_data_anonymized
      iex> event.source_context
      :family
      iex> IntegrationEvent.critical?(event)
      true
  """
  def child_data_anonymized(child_id, payload \\ %{}, opts \\ [])

  def child_data_anonymized(child_id, payload, opts) when is_binary(child_id) and byte_size(child_id) > 0 do
    base_payload = %{child_id: child_id}

    opts = Keyword.put_new(opts, :criticality, :critical)

    IntegrationEvent.new(
      :child_data_anonymized,
      @source_context,
      @entity_type,
      child_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def child_data_anonymized(child_id, _payload, _opts) do
    raise ArgumentError,
          "child_data_anonymized/3 requires a non-empty child_id string, got: #{inspect(child_id)}"
  end

  @doc """
  Creates an `invite_family_ready` integration event.

  Emitted after the Family context creates a parent profile and child record
  from an invite claim. Published on topic `integration:family:invite_family_ready`.

  Uses entity_type `:invite` (not the module-level `@entity_type :child`)
  because this event represents an invite lifecycle transition.

  ## Parameters

  - `invite_id` - The ID of the invite that was claimed
  - `payload` - Event-specific data (invite_id, user_id, child_id, parent_id, program_id)
  - `opts` - Metadata options (correlation_id, causation_id)

  ## Raises

  - `ArgumentError` if `invite_id` is nil or empty

  ## Examples

      iex> event = FamilyIntegrationEvents.invite_family_ready("invite-uuid", %{user_id: "u1"})
      iex> event.event_type
      :invite_family_ready
      iex> event.source_context
      :family
      iex> event.entity_type
      :invite
  """
  def invite_family_ready(invite_id, payload \\ %{}, opts \\ [])

  def invite_family_ready(invite_id, payload, opts) when is_binary(invite_id) and byte_size(invite_id) > 0 do
    base_payload = %{invite_id: invite_id}

    IntegrationEvent.new(
      :invite_family_ready,
      @source_context,
      :invite,
      invite_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def invite_family_ready(invite_id, _payload, _opts) do
    raise ArgumentError,
          "invite_family_ready/3 requires a non-empty invite_id string, got: #{inspect(invite_id)}"
  end
end
