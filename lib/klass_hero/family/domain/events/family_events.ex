defmodule KlassHero.Family.Domain.Events.FamilyEvents do
  @moduledoc """
  Factory module for creating Family events.

  ## Events

  - `:child_created` - Emitted when a new child record is created. Downstream
    contexts (e.g. Messaging) react to maintain local child name lookups.
  - `:child_updated` - Emitted when an existing child record is updated.
    Downstream contexts (e.g. Messaging) react to refresh local child name lookups.
  - `:child_data_anonymized` - Emitted when a child's PII is anonymized during
    GDPR account deletion (critical). Downstream contexts (e.g. Participation)
    react to anonymize their own child-related data.
  - `:invite_family_ready` - Emitted after creating parent + child from an
    invite claim. Downstream contexts (e.g. Enrollment) react to auto-enroll
    the child.

  Each factory takes the entity id, an optional payload, and metadata opts
  (`correlation_id`, `causation_id`, `criticality`), and raises `ArgumentError`
  on a nil or blank id.
  """

  alias KlassHero.Shared.Domain.Events.Event

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
  Creates a `child_created` event.

      iex> event = FamilyEvents.child_created("child-uuid", %{first_name: "Emma"})
      iex> {event.event_type, event.source_context, event.entity_type}
      {:child_created, :family, :child}
  """
  def child_created(child_id, payload \\ %{}, opts \\ [])

  def child_created(child_id, payload, opts) when is_binary(child_id) and byte_size(child_id) > 0 do
    build(:child_created, @entity_type, :child_id, child_id, payload, opts)
  end

  def child_created(child_id, _payload, _opts), do: raise_blank_id(:child_created, :child_id, child_id)

  @doc """
  Creates a `child_updated` event.

      iex> event = FamilyEvents.child_updated("child-uuid", %{first_name: "Emily"})
      iex> event.event_type
      :child_updated
  """
  def child_updated(child_id, payload \\ %{}, opts \\ [])

  def child_updated(child_id, payload, opts) when is_binary(child_id) and byte_size(child_id) > 0 do
    build(:child_updated, @entity_type, :child_id, child_id, payload, opts)
  end

  def child_updated(child_id, _payload, _opts), do: raise_blank_id(:child_updated, :child_id, child_id)

  @doc """
  Creates a `child_data_anonymized` event.

  Critical by default: it is part of the GDPR deletion cascade and must not be lost.

      iex> event = FamilyEvents.child_data_anonymized("child-uuid")
      iex> Event.critical?(event)
      true
  """
  def child_data_anonymized(child_id, payload \\ %{}, opts \\ [])

  def child_data_anonymized(child_id, payload, opts) when is_binary(child_id) and byte_size(child_id) > 0 do
    opts = Keyword.put_new(opts, :criticality, :critical)
    build(:child_data_anonymized, @entity_type, :child_id, child_id, payload, opts)
  end

  def child_data_anonymized(child_id, _payload, _opts) do
    raise_blank_id(:child_data_anonymized, :child_id, child_id)
  end

  @doc """
  Creates an `invite_family_ready` event.

  Carries entity_type `:invite` rather than `:child`, because it marks an
  invite lifecycle transition rather than a change to a child.

      iex> event = FamilyEvents.invite_family_ready("invite-uuid", %{user_id: "u1"})
      iex> {event.event_type, event.entity_type}
      {:invite_family_ready, :invite}
  """
  def invite_family_ready(invite_id, payload \\ %{}, opts \\ [])

  def invite_family_ready(invite_id, payload, opts) when is_binary(invite_id) and byte_size(invite_id) > 0 do
    build(:invite_family_ready, :invite, :invite_id, invite_id, payload, opts)
  end

  def invite_family_ready(invite_id, _payload, _opts) do
    raise_blank_id(:invite_family_ready, :invite_id, invite_id)
  end

  defp build(event_type, entity_type, id_key, id, payload, opts) do
    Event.new(
      event_type,
      @source_context,
      entity_type,
      id,
      # Overwrites rather than merges: the id argument wins over any caller-supplied one.
      Map.put(payload, id_key, id),
      opts
    )
  end

  defp raise_blank_id(event_type, id_key, given) do
    raise ArgumentError,
          "#{event_type}/3 requires a non-empty #{id_key} string, got: #{inspect(given)}"
  end
end
