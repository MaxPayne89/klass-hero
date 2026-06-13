defmodule KlassHero.Messaging.Domain.Events.MessagingIntegrationEvents do
  @moduledoc """
  Factory module for creating Messaging context integration events.

  Integration events are the public contract between bounded contexts.
  They carry stable, versioned payloads with only primitive types.

  ## Events

  - `:message_data_anonymized` - Emitted when a user's messaging data is anonymized
    during GDPR account deletion (critical). Entity type: `:user`.
  - `:conversation_created` - Emitted when a new conversation is created (direct or
    broadcast). Entity type: `:conversation`.
  - `:message_sent` - Emitted when a message is sent to a conversation.
    Entity type: `:conversation`.
  - `:messages_read` - Emitted when a user marks messages as read.
    Entity type: `:conversation`.
  - `:conversation_archived` - Emitted when a single conversation is archived.
    Entity type: `:conversation`.
  - `:conversations_archived` - Emitted when multiple conversations are archived
    in bulk. Entity type: `:conversation`.
  - `:participant_added` - Emitted when one or more users are added to a
    conversation's `participants` table (critical). Entity type: `:conversation`.
  - `:participant_removed` - Emitted when one or more users are removed from a
    conversation's `participants` table (critical). Entity type: `:conversation`.
  """

  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @typedoc "Payload for `:message_data_anonymized` events."
  @type message_data_anonymized_payload :: %{
          required(:user_id) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Payload for `:conversation_created` events."
  @type conversation_created_payload :: %{
          required(:conversation_id) => String.t(),
          required(:participant_ids) => [String.t()],
          required(:provider_id) => String.t(),
          optional(:type) => String.t(),
          optional(:program_id) => String.t() | nil,
          optional(:subject) => String.t() | nil,
          optional(atom()) => term()
        }

  @typedoc "Payload for `:message_sent` events."
  @type message_sent_payload :: %{
          required(:conversation_id) => String.t(),
          required(:sender_id) => String.t(),
          optional(:content) => String.t() | nil,
          optional(:message_type) => String.t() | nil,
          optional(:sent_at) => DateTime.t() | nil,
          optional(:attachments) => [map()],
          optional(atom()) => term()
        }

  @typedoc "Payload for `:messages_read` events."
  @type messages_read_payload :: %{
          required(:conversation_id) => String.t(),
          required(:user_id) => String.t(),
          optional(:read_at) => DateTime.t() | nil,
          optional(atom()) => term()
        }

  @typedoc "Payload for `:conversation_archived` events."
  @type conversation_archived_payload :: %{
          required(:conversation_id) => String.t(),
          optional(:reason) => String.t() | nil,
          optional(:archived_at) => DateTime.t() | nil,
          optional(atom()) => term()
        }

  @typedoc "Payload for `:conversations_archived` events (bulk)."
  @type conversations_archived_payload :: %{
          required(:conversation_ids) => [String.t()],
          optional(:reason) => String.t() | nil,
          optional(:count) => non_neg_integer(),
          optional(atom()) => term()
        }

  @typedoc "Source of a `:participant_added` event."
  @type participant_added_source :: :initial_staff | :later_assignment | :broadcast_setup

  @typedoc "Payload for `:participant_added` events."
  @type participant_added_payload :: %{
          required(:participant_user_ids) => [String.t()],
          required(:source) => participant_added_source(),
          optional(:conversation_id) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "Source of a `:participant_removed` event."
  @type participant_removed_source :: :staff_unassignment

  @typedoc "Payload for `:participant_removed` events."
  @type participant_removed_payload :: %{
          required(:participant_user_ids) => [String.t()],
          required(:source) => participant_removed_source(),
          optional(:conversation_id) => String.t(),
          optional(atom()) => term()
        }

  @source_context :messaging

  @doc """
  Creates a `message_data_anonymized` integration event.

  Marked `:critical` — part of the GDPR deletion cascade and must not be lost.

  Raises `ArgumentError` if `user_id` is nil or empty.
  """
  def message_data_anonymized(user_id, payload \\ %{}, opts \\ [])

  def message_data_anonymized(user_id, payload, opts) when is_binary(user_id) and byte_size(user_id) > 0 do
    base_payload = %{user_id: user_id}

    opts = Keyword.put_new(opts, :criticality, :critical)

    IntegrationEvent.new(
      :message_data_anonymized,
      @source_context,
      :user,
      user_id,
      # Map.merge/2 right-side wins — base_payload overrides any :user_id in caller-supplied payload.
      Map.merge(payload, base_payload),
      opts
    )
  end

  def message_data_anonymized(user_id, _payload, _opts) do
    raise ArgumentError,
          "message_data_anonymized requires a non-empty user_id string, got: #{inspect(user_id)}"
  end

  @doc """
  Creates a `conversation_created` integration event.

  Published when a new conversation is created. Requires `participant_ids` and
  `provider_id` in `payload`. Raises `ArgumentError` if `conversation_id` is nil or empty.
  """
  def conversation_created(conversation_id, payload \\ %{}, opts \\ [])

  def conversation_created(conversation_id, %{participant_ids: _, provider_id: _} = payload, opts)
      when is_binary(conversation_id) and byte_size(conversation_id) > 0 do
    base_payload = %{conversation_id: conversation_id}

    IntegrationEvent.new(
      :conversation_created,
      @source_context,
      :conversation,
      conversation_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def conversation_created(conversation_id, payload, _opts)
      when is_binary(conversation_id) and byte_size(conversation_id) > 0 do
    missing = [:participant_ids, :provider_id] -- Map.keys(payload)

    raise ArgumentError,
          "conversation_created missing required payload keys: #{inspect(missing)}"
  end

  def conversation_created(conversation_id, _payload, _opts) do
    raise ArgumentError,
          "conversation_created/3 requires a non-empty conversation_id string, got: #{inspect(conversation_id)}"
  end

  @doc """
  Creates a `message_sent` integration event.

  Requires `sender_id` in `payload`. Raises `ArgumentError` if `conversation_id` is nil or empty.
  """
  def message_sent(conversation_id, payload \\ %{}, opts \\ [])

  def message_sent(conversation_id, %{sender_id: _} = payload, opts)
      when is_binary(conversation_id) and byte_size(conversation_id) > 0 do
    base_payload = %{conversation_id: conversation_id}

    IntegrationEvent.new(
      :message_sent,
      @source_context,
      :conversation,
      conversation_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def message_sent(conversation_id, payload, _opts)
      when is_binary(conversation_id) and byte_size(conversation_id) > 0 do
    missing = [:sender_id] -- Map.keys(payload)

    raise ArgumentError,
          "message_sent missing required payload keys: #{inspect(missing)}"
  end

  def message_sent(conversation_id, _payload, _opts) do
    raise ArgumentError,
          "message_sent/3 requires a non-empty conversation_id string, got: #{inspect(conversation_id)}"
  end

  @doc """
  Creates a `messages_read` integration event.

  Requires `user_id` in `payload`. Raises `ArgumentError` if `conversation_id` is nil or empty.
  """
  def messages_read(conversation_id, payload \\ %{}, opts \\ [])

  def messages_read(conversation_id, %{user_id: _} = payload, opts)
      when is_binary(conversation_id) and byte_size(conversation_id) > 0 do
    base_payload = %{conversation_id: conversation_id}

    IntegrationEvent.new(
      :messages_read,
      @source_context,
      :conversation,
      conversation_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def messages_read(conversation_id, payload, _opts)
      when is_binary(conversation_id) and byte_size(conversation_id) > 0 do
    missing = [:user_id] -- Map.keys(payload)

    raise ArgumentError,
          "messages_read missing required payload keys: #{inspect(missing)}"
  end

  def messages_read(conversation_id, _payload, _opts) do
    raise ArgumentError,
          "messages_read/3 requires a non-empty conversation_id string, got: #{inspect(conversation_id)}"
  end

  @doc """
  Creates a `conversation_archived` integration event (single conversation).

  Raises `ArgumentError` if `conversation_id` is nil or empty.
  """
  def conversation_archived(conversation_id, payload \\ %{}, opts \\ [])

  def conversation_archived(conversation_id, payload, opts)
      when is_binary(conversation_id) and byte_size(conversation_id) > 0 do
    base_payload = %{conversation_id: conversation_id}

    IntegrationEvent.new(
      :conversation_archived,
      @source_context,
      :conversation,
      conversation_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def conversation_archived(conversation_id, _payload, _opts) do
    raise ArgumentError,
          "conversation_archived/3 requires a non-empty conversation_id string, got: #{inspect(conversation_id)}"
  end

  @doc """
  Creates a `conversations_archived` integration event (bulk).

  `aggregate_id` is a bulk operation identifier (e.g. `"bulk_archive_1234567890"`).
  Requires `conversation_ids` in `payload`. Raises `ArgumentError` if `aggregate_id` is nil or empty.
  """
  def conversations_archived(aggregate_id, payload \\ %{}, opts \\ [])

  def conversations_archived(aggregate_id, %{conversation_ids: _} = payload, opts)
      when is_binary(aggregate_id) and byte_size(aggregate_id) > 0 do
    IntegrationEvent.new(
      :conversations_archived,
      @source_context,
      :conversation,
      aggregate_id,
      payload,
      opts
    )
  end

  def conversations_archived(aggregate_id, payload, _opts)
      when is_binary(aggregate_id) and byte_size(aggregate_id) > 0 do
    missing = [:conversation_ids] -- Map.keys(payload)

    raise ArgumentError,
          "conversations_archived missing required payload keys: #{inspect(missing)}"
  end

  def conversations_archived(aggregate_id, _payload, _opts) do
    raise ArgumentError,
          "conversations_archived/3 requires a non-empty aggregate_id string, got: #{inspect(aggregate_id)}"
  end

  @doc """
  Creates a `participant_added` integration event.

  Marked `:critical` — without durable delivery, late participants would be missing
  from read-model summaries until a server restart re-derives them.

  Requires `participant_user_ids` (non-empty) and `source` in `payload`.
  Raises `ArgumentError` if `conversation_id` is nil or empty, or if required keys are missing.
  """
  def participant_added(conversation_id, payload \\ %{}, opts \\ [])

  def participant_added(conversation_id, %{participant_user_ids: [_ | _] = _ids, source: _source} = payload, opts)
      when is_binary(conversation_id) and byte_size(conversation_id) > 0 do
    base_payload = %{conversation_id: conversation_id}
    opts = Keyword.put_new(opts, :criticality, :critical)

    IntegrationEvent.new(
      :participant_added,
      @source_context,
      :conversation,
      conversation_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def participant_added(conversation_id, %{participant_user_ids: []}, _opts)
      when is_binary(conversation_id) and byte_size(conversation_id) > 0 do
    raise ArgumentError, "participant_added requires a non-empty participant_user_ids list"
  end

  def participant_added(conversation_id, payload, _opts)
      when is_binary(conversation_id) and byte_size(conversation_id) > 0 do
    missing = [:participant_user_ids, :source] -- Map.keys(payload)

    raise ArgumentError,
          "participant_added missing required payload keys: #{inspect(missing)}"
  end

  def participant_added(conversation_id, _payload, _opts) do
    raise ArgumentError,
          "participant_added/3 requires a non-empty conversation_id string, got: #{inspect(conversation_id)}"
  end

  @doc """
  Creates a `participant_removed` integration event.

  Marked `:critical` so CQRS projections soft-remove (archive) read-model summary rows durably.

  Requires `participant_user_ids` (non-empty) and `source` in `payload`.
  Raises `ArgumentError` if `conversation_id` is nil or empty, or if required keys are missing.
  """
  def participant_removed(conversation_id, payload \\ %{}, opts \\ [])

  def participant_removed(conversation_id, %{participant_user_ids: [_ | _] = _ids, source: _source} = payload, opts)
      when is_binary(conversation_id) and byte_size(conversation_id) > 0 do
    base_payload = %{conversation_id: conversation_id}
    opts = Keyword.put_new(opts, :criticality, :critical)

    IntegrationEvent.new(
      :participant_removed,
      @source_context,
      :conversation,
      conversation_id,
      Map.merge(payload, base_payload),
      opts
    )
  end

  def participant_removed(conversation_id, %{participant_user_ids: []}, _opts)
      when is_binary(conversation_id) and byte_size(conversation_id) > 0 do
    raise ArgumentError, "participant_removed requires a non-empty participant_user_ids list"
  end

  def participant_removed(conversation_id, payload, _opts)
      when is_binary(conversation_id) and byte_size(conversation_id) > 0 do
    missing = [:participant_user_ids, :source] -- Map.keys(payload)

    raise ArgumentError,
          "participant_removed missing required payload keys: #{inspect(missing)}"
  end

  def participant_removed(conversation_id, _payload, _opts) do
    raise ArgumentError,
          "participant_removed/3 requires a non-empty conversation_id string, got: #{inspect(conversation_id)}"
  end
end
