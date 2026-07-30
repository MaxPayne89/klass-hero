defmodule KlassHero.Messaging.Domain.Events.MessagingEvents do
  @moduledoc """
  Factory module for creating Messaging events.

  Each factory takes the arguments its producer holds, rather than an id and a
  payload map, and assembles the payload itself — so a producer cannot omit a
  field a consumer needs.

  `:participant_added`, `:participant_removed` and `:message_data_anonymized`
  are critical: without durable delivery, late participants would be missing
  from read-model summaries until a restart re-derived them, removed ones would
  linger, and the GDPR cascade could be lost. Their `source` atom is written
  out as a string, because a critical payload must be a JSON scalar to survive
  Oban's jsonb round trip (see #1010).
  """

  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @source_context :messaging
  @entity_type :conversation

  @doc """
  Creates a conversation_created event.

  Published when a new conversation is created (direct or broadcast).
  """
  @spec conversation_created(
          conversation_id :: String.t(),
          type :: :direct | :program_broadcast,
          provider_id :: String.t(),
          participant_ids :: [String.t()],
          program_id :: String.t() | nil
        ) :: IntegrationEvent.t()
  def conversation_created(conversation_id, type, provider_id, participant_ids, program_id \\ nil) do
    IntegrationEvent.new(
      :conversation_created,
      @source_context,
      @entity_type,
      conversation_id,
      %{
        conversation_id: conversation_id,
        type: type,
        provider_id: provider_id,
        participant_ids: participant_ids,
        program_id: program_id
      }
    )
  end

  @doc """
  Creates a message_sent event.

  The sent_at field is included for real-time display in LiveViews.
  """
  @spec message_sent(
          conversation_id :: String.t(),
          message_id :: String.t(),
          sender_id :: String.t(),
          content :: String.t() | nil,
          message_type :: :text | :system,
          sent_at :: DateTime.t() | nil,
          attachments :: [map()]
        ) :: IntegrationEvent.t()
  def message_sent(conversation_id, message_id, sender_id, content, message_type, sent_at \\ nil, attachments \\ []) do
    IntegrationEvent.new(
      :message_sent,
      @source_context,
      @entity_type,
      conversation_id,
      %{
        conversation_id: conversation_id,
        message_id: message_id,
        sender_id: sender_id,
        content: content,
        message_type: message_type,
        sent_at: sent_at || DateTime.utc_now(),
        attachments: Enum.map(attachments, &serialize_attachment/1)
      }
    )
  end

  defp serialize_attachment(%{id: id, file_url: url, original_filename: name, content_type: ct, file_size_bytes: size}) do
    %{id: id, file_url: url, original_filename: name, content_type: ct, file_size_bytes: size}
  end

  @doc """
  Creates a messages_read event.

  Published when a user marks messages as read.
  """
  @spec messages_read(
          conversation_id :: String.t(),
          user_id :: String.t(),
          read_at :: DateTime.t()
        ) :: IntegrationEvent.t()
  def messages_read(conversation_id, user_id, read_at) do
    IntegrationEvent.new(
      :messages_read,
      @source_context,
      @entity_type,
      conversation_id,
      %{conversation_id: conversation_id, user_id: user_id, read_at: read_at}
    )
  end

  @doc """
  Creates a conversation_archived event (single conversation).
  """
  @spec conversation_archived(
          conversation_id :: String.t(),
          reason :: :program_ended | :manual
        ) :: IntegrationEvent.t()
  def conversation_archived(conversation_id, reason) do
    IntegrationEvent.new(
      :conversation_archived,
      @source_context,
      @entity_type,
      conversation_id,
      %{conversation_id: conversation_id, reason: reason}
    )
  end

  @doc """
  Creates a conversations_archived event for bulk archive operations.

  Published when multiple conversations are archived at once (e.g. program
  ended). Its entity id is a bulk-operation identifier rather than any one
  conversation.
  """
  @spec conversations_archived(
          conversation_ids :: [String.t()],
          reason :: :program_ended | :retention_policy,
          count :: non_neg_integer()
        ) :: IntegrationEvent.t()
  def conversations_archived(conversation_ids, reason, count) do
    IntegrationEvent.new(
      :conversations_archived,
      @source_context,
      @entity_type,
      "bulk_archive_#{DateTime.to_unix(DateTime.utc_now())}",
      %{conversation_ids: conversation_ids, reason: reason, count: count}
    )
  end

  @doc """
  Creates a message_data_anonymized event (critical).

  Published after anonymizing a user's messaging data (content replaced,
  participations ended). Part of the GDPR deletion cascade, so it must not be
  lost.
  """
  @spec message_data_anonymized(user_id :: String.t()) :: IntegrationEvent.t()
  def message_data_anonymized(user_id) when is_binary(user_id) and byte_size(user_id) > 0 do
    IntegrationEvent.new(
      :message_data_anonymized,
      @source_context,
      :user,
      user_id,
      %{user_id: user_id},
      criticality: :critical
    )
  end

  def message_data_anonymized(user_id) do
    raise ArgumentError,
          "message_data_anonymized requires a non-empty user_id string, got: #{inspect(user_id)}"
  end

  @typedoc "Provenance of a participant_added event."
  @type participant_added_source :: :initial_staff | :later_assignment | :broadcast_setup

  @doc """
  Creates a participant_added event (critical).

  Published after one or more users are inserted into a conversation's
  `participants` table. Consumed by CQRS projections.
  """
  @spec participant_added(
          conversation_id :: String.t(),
          participant_user_ids :: [String.t()],
          source :: participant_added_source()
        ) :: IntegrationEvent.t()
  def participant_added(conversation_id, [_ | _] = participant_user_ids, source) do
    participant_event(:participant_added, conversation_id, participant_user_ids, source)
  end

  def participant_added(_conversation_id, [], _source) do
    raise ArgumentError, "participant_added requires a non-empty participant_user_ids list"
  end

  @typedoc "Provenance of a participant_removed event."
  @type participant_removed_source :: :staff_unassignment

  @doc """
  Creates a participant_removed event (critical).

  Published after one or more users are removed from a conversation's
  `participants` table. Consumed by CQRS projections, which soft-archive the
  summary rows.
  """
  @spec participant_removed(
          conversation_id :: String.t(),
          participant_user_ids :: [String.t()],
          source :: participant_removed_source()
        ) :: IntegrationEvent.t()
  def participant_removed(conversation_id, [_ | _] = participant_user_ids, source) do
    participant_event(:participant_removed, conversation_id, participant_user_ids, source)
  end

  def participant_removed(_conversation_id, [], _source) do
    raise ArgumentError, "participant_removed requires a non-empty participant_user_ids list"
  end

  defp participant_event(event_type, conversation_id, participant_user_ids, source) do
    IntegrationEvent.new(
      event_type,
      @source_context,
      @entity_type,
      conversation_id,
      %{
        conversation_id: conversation_id,
        participant_user_ids: participant_user_ids,
        # Critical payload must be a JSON scalar; the atom source is write-only (see #1010).
        source: to_string(source)
      },
      criticality: :critical
    )
  end
end
