defmodule KlassHero.Family.Domain.Events.FamilyEvents do
  @moduledoc """
  Factory module for creating Family domain events.

  Provides convenience functions to create standardized DomainEvent structs
  for family-related events.

  ## Events

  - `:child_created` - Emitted when a new child record is created. Downstream
    contexts (e.g. Messaging) react to maintain local child name lookups.
  - `:child_updated` - Emitted when an existing child record is updated.
    Downstream contexts (e.g. Messaging) react to refresh local child name lookups.
  - `:child_data_anonymized` - Emitted when a child's PII is anonymized during
    GDPR account deletion (critical). Downstream contexts (e.g. Participation)
    react to this event to anonymize their own child-related data.
  - `:invite_family_ready` - Emitted after creating parent + child from an
    invite claim. Signals that the family unit is set up and enrollment can
    proceed.
  """

  alias KlassHero.Shared.Domain.Events.DomainEvent

  @aggregate_type :child

  @doc """
  Creates a `child_created` event.

  Emitted when a new child record is created. Downstream contexts (e.g.
  Messaging) react to maintain a local lookup of child names.

  ## Parameters

  - `child_id` - The ID of the newly created child
  - `payload` - Additional event-specific data (child_id, parent_id, first_name, last_name)
  - `opts` - Metadata options (correlation_id, causation_id, user_id)

  ## Raises

  - `ArgumentError` if `child_id` is nil or empty

  ## Examples

      iex> event = FamilyEvents.child_created("child-uuid", %{first_name: "Emma"})
      iex> event.event_type
      :child_created
  """
  def child_created(child_id, payload \\ %{}, opts \\ [])

  def child_created(child_id, payload, opts) when is_binary(child_id) and byte_size(child_id) > 0 do
    base_payload = %{child_id: child_id}

    DomainEvent.new(
      :child_created,
      child_id,
      @aggregate_type,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def child_created(child_id, _payload, _opts) do
    raise ArgumentError,
          "child_created/3 requires a non-empty child_id string, got: #{inspect(child_id)}"
  end

  @doc """
  Creates a `child_updated` event.

  Emitted when an existing child record is updated. Downstream contexts (e.g.
  Messaging) react to refresh their local lookup of child names.

  ## Parameters

  - `child_id` - The ID of the updated child
  - `payload` - Additional event-specific data (child_id, first_name, last_name)
  - `opts` - Metadata options (correlation_id, causation_id, user_id)

  ## Raises

  - `ArgumentError` if `child_id` is nil or empty

  ## Examples

      iex> event = FamilyEvents.child_updated("child-uuid", %{first_name: "Emily"})
      iex> event.event_type
      :child_updated
  """
  def child_updated(child_id, payload \\ %{}, opts \\ [])

  def child_updated(child_id, payload, opts) when is_binary(child_id) and byte_size(child_id) > 0 do
    base_payload = %{child_id: child_id}

    DomainEvent.new(
      :child_updated,
      child_id,
      @aggregate_type,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def child_updated(child_id, _payload, _opts) do
    raise ArgumentError,
          "child_updated/3 requires a non-empty child_id string, got: #{inspect(child_id)}"
  end

  @doc """
  Creates a `child_data_anonymized` event.

  This event is marked as `:critical` by default since it is part of the
  GDPR deletion cascade and must not be lost.

  ## Parameters

  - `child_id` - The ID of the child whose data was anonymized
  - `payload` - Additional event-specific data
  - `opts` - Metadata options (correlation_id, causation_id, user_id)

  ## Payload Fields

  Standard payload includes:
  - `child_id` - The child's ID

  ## Raises

  - `ArgumentError` if `child_id` is nil or empty

  ## Examples

      iex> event = FamilyEvents.child_data_anonymized("child-uuid")
      iex> event.event_type
      :child_data_anonymized
      iex> DomainEvent.critical?(event)
      true
  """
  def child_data_anonymized(child_id, payload \\ %{}, opts \\ [])

  def child_data_anonymized(child_id, payload, opts) when is_binary(child_id) and byte_size(child_id) > 0 do
    base_payload = %{child_id: child_id}

    opts = Keyword.put_new(opts, :criticality, :critical)

    DomainEvent.new(
      :child_data_anonymized,
      child_id,
      @aggregate_type,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def child_data_anonymized(child_id, _payload, _opts) do
    raise ArgumentError,
          "child_data_anonymized/3 requires a non-empty child_id string, got: #{inspect(child_id)}"
  end

  @doc """
  Creates an `invite_family_ready` event.

  Emitted after the Family context creates a parent profile and child record
  from an invite claim. Downstream contexts (e.g. Enrollment) react to this
  event to auto-enroll the child into the invited program.

  ## Parameters

  - `invite_id` - The ID of the invite that was claimed
  - `payload` - Event-specific data (invite_id, user_id, child_id, parent_id, program_id)
  - `opts` - Metadata options (correlation_id, causation_id, user_id)

  ## Raises

  - `ArgumentError` if `invite_id` is nil or empty

  ## Examples

      iex> event = FamilyEvents.invite_family_ready("invite-uuid", %{user_id: "u1"})
      iex> event.event_type
      :invite_family_ready
  """
  def invite_family_ready(invite_id, payload \\ %{}, opts \\ [])

  def invite_family_ready(invite_id, payload, opts) when is_binary(invite_id) and byte_size(invite_id) > 0 do
    base_payload = %{invite_id: invite_id}

    DomainEvent.new(
      :invite_family_ready,
      invite_id,
      :invite,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def invite_family_ready(invite_id, _payload, _opts) do
    raise ArgumentError,
          "invite_family_ready/3 requires a non-empty invite_id string, got: #{inspect(invite_id)}"
  end
end
