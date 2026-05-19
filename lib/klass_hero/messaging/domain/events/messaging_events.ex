defmodule KlassHero.Messaging.Domain.Events.MessagingEvents do
  @moduledoc """
  Factory module for creating messaging domain events.

  These events are internal to the Messaging context and drive real-time
  LiveView updates via PubSub. They are not intended for cross-context
  communication.

  For cross-context integration events, see
  `KlassHero.Messaging.Domain.Events.MessagingIntegrationEvents`.
  """

  alias KlassHero.Shared.Domain.Events.DomainEvent

  @aggregate_type :conversation

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
        ) :: DomainEvent.t()
  def conversation_created(conversation_id, type, provider_id, participant_ids, program_id \\ nil) do
    DomainEvent.new(
      :conversation_created,
      conversation_id,
      @aggregate_type,
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

  Published when a message is sent to a conversation.
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
        ) :: DomainEvent.t()
  def message_sent(conversation_id, message_id, sender_id, content, message_type, sent_at \\ nil, attachments \\ []) do
    DomainEvent.new(
      :message_sent,
      conversation_id,
      @aggregate_type,
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
        ) :: DomainEvent.t()
  def messages_read(conversation_id, user_id, read_at) do
    DomainEvent.new(
      :messages_read,
      conversation_id,
      @aggregate_type,
      %{
        conversation_id: conversation_id,
        user_id: user_id,
        read_at: read_at
      }
    )
  end

  @doc """
  Creates a conversation_archived event.

  Published when a conversation is archived.
  """
  @spec conversation_archived(
          conversation_id :: String.t(),
          reason :: :program_ended | :manual
        ) :: DomainEvent.t()
  def conversation_archived(conversation_id, reason) do
    DomainEvent.new(
      :conversation_archived,
      conversation_id,
      @aggregate_type,
      %{
        conversation_id: conversation_id,
        reason: reason
      }
    )
  end

  @doc """
  Creates a conversations_archived event for bulk archive operations.

  Published when multiple conversations are archived at once (e.g., program ended).
  """
  @spec conversations_archived(
          conversation_ids :: [String.t()],
          reason :: :program_ended | :retention_policy,
          count :: non_neg_integer()
        ) :: DomainEvent.t()
  def conversations_archived(conversation_ids, reason, count) do
    aggregate_id = "bulk_archive_#{DateTime.to_unix(DateTime.utc_now())}"

    DomainEvent.new(
      :conversations_archived,
      aggregate_id,
      @aggregate_type,
      %{
        conversation_ids: conversation_ids,
        reason: reason,
        count: count
      }
    )
  end

  @doc """
  Creates a retention_enforced event.

  Published when retention policy is enforced, deleting expired messages and conversations.
  """
  @spec retention_enforced(
          messages_deleted :: non_neg_integer(),
          conversations_deleted :: non_neg_integer()
        ) :: DomainEvent.t()
  def retention_enforced(messages_deleted, conversations_deleted) do
    aggregate_id = "retention_#{DateTime.to_unix(DateTime.utc_now())}"

    DomainEvent.new(
      :retention_enforced,
      aggregate_id,
      @aggregate_type,
      %{
        messages_deleted: messages_deleted,
        conversations_deleted: conversations_deleted,
        enforced_at: DateTime.utc_now()
      }
    )
  end

  @doc """
  Creates a user_data_anonymized event.

  Published after anonymizing a user's messaging data (content replaced,
  participations ended). Handlers may promote this to an integration event
  for cross-context notification.
  """
  @spec user_data_anonymized(user_id :: String.t()) :: DomainEvent.t()
  def user_data_anonymized(user_id) do
    DomainEvent.new(
      :user_data_anonymized,
      user_id,
      :user,
      %{user_id: user_id}
    )
  end

  @typedoc "Provenance of a participant_added event."
  @type participant_added_source :: :initial_staff | :later_assignment | :broadcast_setup

  @doc """
  Creates a participant_added event.

  Published after one or more users are inserted into a conversation's
  `participants` table. Promoted to a critical integration event for
  CQRS projections.
  """
  @spec participant_added(
          conversation_id :: String.t(),
          participant_user_ids :: [String.t()],
          source :: participant_added_source()
        ) :: DomainEvent.t()
  def participant_added(conversation_id, participant_user_ids, source) do
    DomainEvent.new(
      :participant_added,
      conversation_id,
      @aggregate_type,
      %{
        conversation_id: conversation_id,
        participant_user_ids: participant_user_ids,
        source: source
      }
    )
  end

  @typedoc "Provenance of a participant_removed event."
  @type participant_removed_source :: :staff_unassignment

  @doc """
  Creates a participant_removed event.

  Published after one or more users are removed from a conversation's
  `participants` table. Promoted to a critical integration event for
  CQRS projections (soft-archives summary rows).
  """
  @spec participant_removed(
          conversation_id :: String.t(),
          participant_user_ids :: [String.t()],
          source :: participant_removed_source()
        ) :: DomainEvent.t()
  def participant_removed(conversation_id, participant_user_ids, source) do
    DomainEvent.new(
      :participant_removed,
      conversation_id,
      @aggregate_type,
      %{
        conversation_id: conversation_id,
        participant_user_ids: participant_user_ids,
        source: source
      }
    )
  end
end
