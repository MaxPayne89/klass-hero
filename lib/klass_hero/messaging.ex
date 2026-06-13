defmodule KlassHero.Messaging do
  @moduledoc """
  Public API facade for the Messaging bounded context.

  This module provides the primary interface for messaging functionality:
  - Direct 1-on-1 conversations between providers and parents
  - Program broadcast messages to all enrolled parents
  - Real-time message delivery via PubSub

  ## Conversation Types

  - `:direct` - Private conversation between one provider and one parent
  - `:program_broadcast` - Announcement from provider to all enrolled parents

  ## Entitlements

  Free-tier parents cannot initiate conversations but can receive and reply.
  Use `KlassHero.Shared.Entitlements.can_initiate_messaging?/1` to check permissions.

  ## Real-time Updates

  Subscribe to PubSub topics for real-time updates:
  - `"conversation:{id}"` - Per-conversation updates
  - `"user:{id}:messages"` - User notification updates
  """

  use Boundary,
    top_level?: true,
    deps: [
      KlassHero,
      KlassHero.Accounts,
      KlassHero.Enrollment,
      KlassHero.ProgramCatalog,
      KlassHero.Provider,
      KlassHero.Shared
    ],
    exports: [
      Domain.Models.Attachment,
      Domain.Models.Message,
      Domain.Models.Conversation,
      Domain.Models.Participant,
      Domain.Models.InboundEmail,
      Domain.Models.EmailReply
    ]

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.Adapters.Driven.EmailSanitizer
  alias KlassHero.Messaging.Adapters.Driving.Events.EventHandlers.NotifyLiveViews

  alias KlassHero.Messaging.Application.Commands.{
    AnonymizeUserData,
    BroadcastToProgram,
    CreateDirectConversation,
    MarkAsRead,
    ReceiveInboundEmail,
    ReplyPrivatelyToBroadcast,
    ReplyToEmail,
    ScheduleEmailContentFetch,
    SendMessage,
    StartProgramConversation,
    UpdateInboundEmailContent,
    UpdateInboundEmailStatus
  }

  alias KlassHero.Messaging.Application.Queries.{
    GetConversation,
    GetConversationContext,
    GetInboundEmail,
    GetTotalUnreadCount,
    InboundEmailQueries,
    ListConversations,
    ListInboundEmails,
    ResolverQueries
  }

  alias KlassHero.Messaging.Domain.Models.{Conversation, EmailReply, Message, Participant}

  @doc """
  Creates or retrieves a direct conversation between provider and user.

  If a direct conversation already exists, returns it.
  Otherwise creates a new one.

  ## Parameters
  - scope: The initiating user's scope (for entitlement checks)
  - provider_id: The provider's profile ID
  - target_user_id: The user ID to converse with

  ## Returns
  - `{:ok, conversation}` - The new or existing conversation
  - `{:error, :not_entitled}` - User cannot initiate messaging

  ## Examples

      iex> Messaging.create_direct_conversation(scope, provider_id, parent_user_id)
      {:ok, %Conversation{type: :direct, ...}}

  """
  @spec create_direct_conversation(Scope.t(), String.t(), String.t(), keyword()) ::
          {:ok, Conversation.t()} | {:error, :not_entitled | term()}
  def create_direct_conversation(scope, provider_id, target_user_id, opts \\ []) do
    CreateDirectConversation.execute(scope, provider_id, target_user_id, opts)
  end

  @doc """
  Starts (or retrieves) a direct conversation between a parent and a provider
  in the context of a specific program.

  Resolves the provider owner automatically and auto-adds program-assigned
  staff as participants. Intended for parent-initiated flows where the UI
  only knows the `program_id` and `provider_id`.

  ## Parameters
  - scope: The parent's scope (for entitlement checks)
  - provider_id: The provider profile ID
  - program_id: The program being discussed

  ## Returns
  - `{:ok, conversation}` - New or existing direct conversation
  - `{:error, :not_found}` - Provider does not exist
  - `{:error, :not_entitled}` - Parent cannot initiate messaging
  """
  @spec start_program_conversation(Scope.t(), String.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, :not_found | :not_entitled | term()}
  defdelegate start_program_conversation(scope, provider_id, program_id),
    to: StartProgramConversation,
    as: :execute

  @doc """
  Sends a message to a conversation.

  The sender must be a participant in the conversation.

  ## Parameters
  - conversation_id: The conversation to send to
  - sender_id: The user sending the message
  - content: The message content
  - opts: Optional parameters
    - message_type: :text (default) or :system

  ## Returns
  - `{:ok, message}` - Message sent successfully
  - `{:error, :not_participant}` - Sender is not in the conversation

  ## Examples

      iex> Messaging.send_message(conversation_id, sender_id, "Hello!")
      {:ok, %Message{content: "Hello!", ...}}

  """
  @spec send_message(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Message.t()} | {:error, :not_participant | :broadcast_reply_not_allowed | term()}
  defdelegate send_message(conversation_id, sender_id, content, opts \\ []),
    to: SendMessage,
    as: :execute

  @doc """
  Marks messages as read in a conversation.

  Updates the participant's last_read_at timestamp.

  ## Parameters
  - conversation_id: The conversation
  - user_id: The user marking as read
  - read_at: Optional timestamp (defaults to now)

  ## Returns
  - `{:ok, participant}` - Updated participant
  - `{:error, :not_participant}` - User is not in the conversation

  ## Examples

      iex> Messaging.mark_as_read(conversation_id, user_id)
      {:ok, %Participant{last_read_at: ~U[...], ...}}

  """
  @spec mark_as_read(String.t(), String.t(), DateTime.t() | nil) ::
          {:ok, Participant.t()} | {:error, :not_participant}
  defdelegate mark_as_read(conversation_id, user_id, read_at \\ nil),
    to: MarkAsRead,
    as: :execute

  @doc """
  Sends a broadcast message to all enrolled parents of a program.

  Creates a program broadcast conversation if one doesn't exist,
  adds all enrolled parents as participants, and sends the message.

  ## Parameters
  - scope: The provider's scope (for entitlement checks)
  - program_id: The program to broadcast to
  - content: The message content
  - opts: Optional parameters
    - subject: Subject line for the broadcast

  ## Returns
  - `{:ok, conversation, message, recipient_count}` - Broadcast sent
  - `{:error, :not_entitled}` - Provider cannot send broadcasts
  - `{:error, :no_enrollments}` - No enrolled parents

  ## Examples

      iex> Messaging.broadcast_to_program(scope, program_id, "Important update!")
      {:ok, %Conversation{type: :program_broadcast}, %Message{}, 15}

  """
  @spec broadcast_to_program(Scope.t(), String.t(), String.t(), keyword()) ::
          {:ok, Conversation.t(), Message.t(), non_neg_integer()}
          | {:error, :not_entitled | :no_enrollments | term()}
  defdelegate broadcast_to_program(scope, program_id, content, opts \\ []),
    to: BroadcastToProgram,
    as: :execute

  @doc """
  Initiates a private reply to a broadcast message.

  Creates (or finds) a direct conversation between the parent and the
  broadcast's provider, inserts a context system message, and returns
  the direct conversation ID for navigation.

  ## Parameters
  - scope: The parent's scope
  - broadcast_conversation_id: The broadcast being replied to

  ## Returns
  - `{:ok, direct_conversation_id}` - Ready for messaging
  - `{:error, :not_found}` - Broadcast not found
  - `{:error, reason}` - Other errors

  ## Examples

      iex> Messaging.reply_privately_to_broadcast(scope, broadcast_id)
      {:ok, "direct-conversation-uuid"}

  """
  @spec reply_privately_to_broadcast(Scope.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  defdelegate reply_privately_to_broadcast(scope, broadcast_conversation_id),
    to: ReplyPrivatelyToBroadcast,
    as: :execute

  @doc """
  Anonymizes all messaging data for a user as part of GDPR deletion.

  Replaces message content with `"[deleted]"` and marks all active
  conversation participations as left. Publishes a `message_data_anonymized`
  integration event on success.

  ## Parameters
  - user_id: The ID of the user to anonymize

  ## Returns
  - `{:ok, %{messages_anonymized: n, participants_updated: n}}` - Success
  - `{:error, reason}` - Failure

  ## Examples

      iex> Messaging.anonymize_data_for_user(user_id)
      {:ok, %{messages_anonymized: 5, participants_updated: 2}}

  """
  @spec anonymize_data_for_user(String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate anonymize_data_for_user(user_id), to: AnonymizeUserData, as: :execute

  @doc """
  Stores an inbound email received via webhook.

  Handles deduplication by resend_id — returns `{:ok, :duplicate}` for
  already-stored emails so callers can acknowledge without re-processing.

  ## Parameters
  - attrs: Map with inbound email attributes (resend_id, from_address, subject, etc.)

  ## Returns
  - `{:ok, inbound_email}` - Email stored successfully
  - `{:ok, :duplicate}` - Email already exists (idempotent)
  - `{:error, reason}` - Storage failure

  ## Examples

      iex> Messaging.receive_inbound_email(%{resend_id: "...", from_address: "sender@example.com", ...})
      {:ok, %InboundEmail{}}

  """
  @spec receive_inbound_email(map()) :: {:ok, struct()} | {:ok, :duplicate} | {:error, term()}
  defdelegate receive_inbound_email(attrs), to: ReceiveInboundEmail, as: :execute

  @doc """
  Replies to an inbound email by sending a response via Swoosh/Resend.

  ## Parameters
  - `email_id` - The inbound email to reply to
  - `reply_body` - The reply text content
  - `sent_by_id` - The ID of the user sending the reply

  ## Returns
  - `{:ok, email_reply}` - Reply sent and recorded successfully
  - `{:error, reason}` - Failed to send
  """
  @spec reply_to_inbound_email(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, EmailReply.t()} | {:error, term()}
  defdelegate reply_to_inbound_email(email_id, reply_body, sent_by_id, opts \\ []),
    to: ReplyToEmail,
    as: :execute

  @doc """
  Schedules a content fetch retry for an inbound email.

  ## Parameters
  - `email_id` - The inbound email ID
  - `resend_id` - The Resend email ID for the API call
  """
  @spec schedule_content_fetch(String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  defdelegate schedule_content_fetch(email_id, resend_id),
    to: ScheduleEmailContentFetch,
    as: :execute

  @doc "Updates inbound email content fields (body, headers, content_status)."
  @spec update_inbound_email_content(String.t(), map()) ::
          {:ok, struct()} | {:error, term()}
  defdelegate update_inbound_email_content(id, attrs),
    to: UpdateInboundEmailContent,
    as: :execute

  @doc """
  Updates the status of an inbound email.

  ## Parameters
  - `id` - The email ID
  - `status` - The new status string ("unread", "read", "archived")
  - `attrs` - Additional attributes to update

  ## Returns
  - `{:ok, email}` - Updated email
  - `{:error, reason}` - Failure
  """
  @spec update_inbound_email_status(String.t(), String.t(), map()) ::
          {:ok, struct()} | {:error, term()}
  defdelegate update_inbound_email_status(id, status, attrs \\ %{}),
    to: UpdateInboundEmailStatus,
    as: :execute

  @doc """
  Subscribes to real-time updates for a conversation.

  ## Examples

      iex> Messaging.subscribe_to_conversation(conversation_id)
      :ok

  """
  @spec subscribe_to_conversation(String.t()) :: :ok | {:error, term()}
  def subscribe_to_conversation(conversation_id) do
    Phoenix.PubSub.subscribe(KlassHero.PubSub, conversation_topic(conversation_id))
  end

  @doc """
  Subscribes to real-time updates for a user's messages.

  ## Examples

      iex> Messaging.subscribe_to_user_messages(user_id)
      :ok

  """
  @spec subscribe_to_user_messages(String.t()) :: :ok | {:error, term()}
  def subscribe_to_user_messages(user_id) do
    Phoenix.PubSub.subscribe(KlassHero.PubSub, user_messages_topic(user_id))
  end

  @doc """
  Retrieves a conversation with its messages.

  ## Parameters
  - conversation_id: The conversation to retrieve
  - user_id: The requesting user (for access control)
  - opts: Optional parameters
    - limit: Number of messages (default 50)
    - before: Get messages before this timestamp
    - mark_as_read: Whether to mark messages as read (default false)

  ## Returns
  - `{:ok, result_map}` - Success, with keys:
    - `:conversation` - The conversation entity
    - `:messages` - List of messages
    - `:has_more` - Whether there are more messages
    - `:sender_names` - Map of sender_id => display name
  - `{:error, :not_found}` - Conversation doesn't exist
  - `{:error, :not_participant}` - User is not in the conversation

  ## Examples

      iex> Messaging.get_conversation(conversation_id, user_id)
      {:ok, %{conversation: %Conversation{}, messages: [...], has_more: false, sender_names: %{}}}

  """
  @spec get_conversation(String.t(), String.t(), keyword()) ::
          {:ok, map()}
          | {:error, :not_found | :not_participant}
  defdelegate get_conversation(conversation_id, user_id, opts \\ []),
    to: GetConversation,
    as: :execute

  @doc """
  Lists conversations for a user with unread counts.

  Returns conversations ordered by most recent message.

  ## Parameters
  - user_id: The user to list conversations for
  - opts: Optional parameters
    - limit: Number of conversations (default 50)

  ## Returns
  - `{:ok, conversations, has_more}` - List of enriched conversations

  Each conversation includes:
  - `:conversation` - The conversation entity
  - `:unread_count` - Number of unread messages
  - `:latest_message` - The most recent message
  - `:last_read_at` - When user last read

  ## Examples

      iex> Messaging.list_conversations(user_id)
      {:ok, [%{conversation: %Conversation{}, unread_count: 2, ...}], false}

  """
  @spec list_conversations(String.t(), keyword()) :: {:ok, [map()], boolean()}
  defdelegate list_conversations(user_id, opts \\ []),
    to: ListConversations,
    as: :execute

  @doc """
  Gets the total unread message count across all conversations for a user.

  This is useful for displaying an unread badge in the navigation.

  ## Parameters
  - user_id: The user to get unread count for

  ## Returns
  - Non-negative integer count of unread messages

  ## Examples

      iex> Messaging.get_total_unread_count(user_id)
      5

  """
  @spec get_total_unread_count(String.t()) :: non_neg_integer()
  defdelegate get_total_unread_count(user_id),
    to: GetTotalUnreadCount,
    as: :execute

  @doc """
  Returns enrolled child names and other participant name for a conversation/user pair.

  Used by the web layer to build enriched conversation titles, e.g. "Sarah for Emma, Liam".
  Reads from the denormalized conversation_summaries read model.

  ## Parameters
  - conversation_id: The conversation to look up
  - user_id: The requesting user's ID

  ## Returns
  - Map with `:enrolled_child_names` (list) and `:other_participant_name` (string or nil)
  """
  @spec get_conversation_context(String.t(), String.t()) ::
          %{enrolled_child_names: [String.t()], other_participant_name: String.t() | nil}
  defdelegate get_conversation_context(conversation_id, user_id),
    to: GetConversationContext,
    as: :execute

  @doc """
  Lists inbound emails with optional filtering.

  ## Options
  - `:limit` - Max emails to return (default 50)
  - `:status` - Filter by status atom (:unread, :read, :archived)

  ## Returns
  - `{:ok, emails, has_more}` - List of inbound emails with pagination flag
  """
  @spec list_inbound_emails(keyword()) :: {:ok, [struct()], boolean()}
  defdelegate list_inbound_emails(opts \\ []), to: ListInboundEmails, as: :execute

  @doc """
  Retrieves an inbound email by ID, optionally marking it as read.

  ## Options
  - `:mark_read` - Whether to mark the email as read (default false)
  - `:reader_id` - The ID of the user reading the email

  ## Returns
  - `{:ok, email}` - The inbound email
  - `{:error, :not_found}` - Email not found
  """
  @spec get_inbound_email(String.t(), keyword()) :: {:ok, struct()} | {:error, :not_found}
  defdelegate get_inbound_email(id, opts \\ []), to: GetInboundEmail, as: :execute

  @doc """
  Lists all email replies for a given inbound email.

  ## Parameters
  - `inbound_email_id` - The ID of the inbound email

  ## Returns
  - `{:ok, replies}` - List of email replies
  """
  @spec list_email_replies(String.t()) :: {:ok, [EmailReply.t()]}
  defdelegate list_email_replies(inbound_email_id),
    to: InboundEmailQueries,
    as: :list_replies

  @doc """
  Sanitizes inbound email HTML for safe rendering.

  Strips dangerous tags (script, iframe, style) and event handlers.
  By default blocks external images to prevent tracking pixels.

  ## Options
  - `:allow_images` - Whether to allow external images (default false)

  ## Returns
  - Sanitized HTML string
  """
  @spec sanitize_email_html(String.t() | nil, keyword()) :: String.t()
  defdelegate sanitize_email_html(html, opts \\ []), to: EmailSanitizer, as: :sanitize

  @doc """
  Returns the count of inbound emails with the given status.

  ## Examples

      iex> Messaging.count_inbound_emails_by_status(:unread)
      3

  """
  @spec count_inbound_emails_by_status(atom()) :: non_neg_integer()
  defdelegate count_inbound_emails_by_status(status),
    to: InboundEmailQueries,
    as: :count_by_status

  @doc """
  Returns the display name for a user.

  Used by LiveView helpers to resolve sender names for real-time messages.
  """
  @spec get_display_name(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  defdelegate get_display_name(user_id), to: ResolverQueries

  @doc """
  Returns the user IDs of active staff assigned to a program.

  Used by the web layer to determine which message senders are on the
  provider side, for branded attribution display ("Business via Staff Name").

  ## Parameters
  - program_id: The program to look up staff for

  ## Returns
  - List of user ID strings
  """
  @spec get_active_staff_user_ids(String.t()) :: [String.t()]
  defdelegate get_active_staff_user_ids(program_id), to: ResolverQueries

  @doc """
  Returns the PubSub topic for a conversation.

  Used by LiveViews to subscribe to real-time updates for a specific conversation.
  """
  @spec conversation_topic(String.t()) :: String.t()
  defdelegate conversation_topic(conversation_id), to: NotifyLiveViews

  @doc """
  Returns the PubSub topic for a user's message notifications.

  Used by LiveViews to subscribe to new conversation and message notifications.
  """
  @spec user_messages_topic(String.t()) :: String.t()
  defdelegate user_messages_topic(user_id), to: NotifyLiveViews
end
