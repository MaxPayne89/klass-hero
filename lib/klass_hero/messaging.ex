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

  ## Messaging permission

  Any parent or provider (including staff acting for a loaded provider) may
  initiate conversations. Use `can_initiate_messaging?/1` to check a scope.

  ## Real-time Updates

  Subscribe to PubSub topics for real-time updates:
  - `"conversation:{id}"` - Per-conversation updates
  - `"user:{id}:messages"` - User notification updates
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Accounts
  alias KlassHero.Accounts.Scope

  alias KlassHero.Messaging.{
    AnonymizeUserData,
    Authorization,
    BroadcastToProgram,
    CreateDirectConversation,
    GetConversation,
    GetConversationContext,
    GetInboundEmail,
    GetMonitoredConversation,
    GetStaffConversation,
    GetTotalUnreadCount,
    ListStaffConversations,
    MarkAsRead,
    MonitorConversations,
    ReceiveInboundEmail,
    ReplyPrivatelyToBroadcast,
    ReplyToEmail,
    ScheduleEmailContentFetch,
    SendMessage,
    StartConversationWithMessage
  }

  alias KlassHero.Messaging.Attachment
  alias KlassHero.Messaging.ComposeTarget
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.EmailReply
  alias KlassHero.Messaging.EmailSanitizer
  alias KlassHero.Messaging.InboundEmail
  alias KlassHero.Messaging.InboxConversation
  alias KlassHero.Messaging.ListConversations
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.Notifications
  alias KlassHero.Messaging.Participant
  alias KlassHero.Messaging.Queries.ConversationQueries
  alias KlassHero.Messaging.Queries.InboundEmailQueries
  alias KlassHero.Messaging.Queries.MessageQueries
  alias KlassHero.Messaging.StaffConversation
  alias KlassHero.Repo

  require Logger

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

      Messaging.create_direct_conversation(scope, provider_id, parent_user_id)
      #=> {:ok, %Conversation{type: :direct, ...}}

  """
  @spec create_direct_conversation(Scope.t(), String.t(), String.t(), keyword()) ::
          {:ok, Conversation.t()} | {:error, :not_entitled | term()}
  def create_direct_conversation(scope, provider_id, target_user_id, opts \\ []) do
    CreateDirectConversation.execute(scope, provider_id, target_user_id, opts)
  end

  @doc """
  Returns whether the given scope may initiate messaging.

  Any parent or provider (including a staff member whose provider is loaded)
  may initiate. A pure staff-only scope (staff_member set but no provider and
  no parent) and any unrecognised scope shape are denied.
  """
  @spec can_initiate_messaging?(map()) :: boolean()
  def can_initiate_messaging?(%{staff_member: %{provider_id: _}, provider: nil, parent: nil}), do: false
  def can_initiate_messaging?(%{parent: parent, provider: provider}), do: not is_nil(parent) or not is_nil(provider)
  def can_initiate_messaging?(%{parent: parent}), do: not is_nil(parent)
  def can_initiate_messaging?(%{provider: provider}), do: not is_nil(provider)
  def can_initiate_messaging?(_scope), do: false

  @doc """
  Resolves who a compose screen is writing to, refusing targets the scope may not write to.

  The gate lives here rather than in the callers: the compose screen renders the
  target's name, so a hand-typed URL must fail before it discloses one.

  ## Options
  - `:target_user_id` — required when a provider or staff member writes to a parent
  - `:program_id` — required for that direction, since the roster check is per-program
  """
  @spec build_compose_target(map(), String.t(), keyword()) ::
          {:ok, ComposeTarget.t()} | {:error, :not_found | :unauthorized}
  def build_compose_target(scope, provider_id, opts \\ []) do
    program_id = Keyword.get(opts, :program_id)

    with {:ok, target_user_id, target_name} <-
           resolve_compose_target(provider_id, Keyword.get(opts, :target_user_id)),
         :ok <- Authorization.authorize_compose(scope, provider_id, target_user_id, program_id) do
      {:ok,
       %ComposeTarget{
         provider_id: provider_id,
         target_user_id: target_user_id,
         program_id: program_id,
         target_name: target_name
       }}
    end
  end

  # No named target means the business itself. One rule covers a parent writing to
  # a provider and a staff member writing to their employer; the business name is
  # what either of them expects to see at the top of the thread.
  defp resolve_compose_target(provider_id, nil) do
    acl_span source: "messaging", target: "provider" do
      case KlassHero.Provider.get_provider_profile(provider_id) do
        {:ok, provider} -> {:ok, provider.identity_id, provider.business_name}
        {:error, _reason} -> {:error, :not_found}
      end
    end
  end

  defp resolve_compose_target(_provider_id, target_user_id) when is_binary(target_user_id) do
    {:ok, target_user_id, Map.get(Accounts.get_display_names([target_user_id]), target_user_id)}
  end

  defp resolve_compose_target(_provider_id, _target_user_id), do: {:error, :unauthorized}

  @doc """
  Opens a direct conversation and sends its first message in one call.

  The only way a compose screen creates a conversation — see
  `StartConversationWithMessage` for why creation waits for the message.
  """
  @spec start_conversation_with_message(
          Scope.t(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          keyword()
        ) ::
          {:ok, Conversation.t(), Message.t()}
          | {:error, :empty_message | :not_entitled | :not_found | term()}
  def start_conversation_with_message(scope, provider_id, target_user_id, content, opts \\ []) do
    StartConversationWithMessage.execute(scope, provider_id, target_user_id, content, opts)
  end

  @doc """
  Returns whether `scope` may open a conversation with `parent_user_id` about `program_id`.

  Gates the compose screen: the target's name is rendered there, so a hand-typed
  URL must be refused before it discloses anything.
  """
  @spec can_message_parent?(map(), String.t(), String.t(), String.t()) :: boolean()
  def can_message_parent?(scope, provider_id, program_id, parent_user_id)
      when is_binary(provider_id) and is_binary(program_id) and is_binary(parent_user_id) do
    Authorization.authorize_compose(scope, provider_id, parent_user_id, program_id) == :ok
  end

  def can_message_parent?(_scope, _provider_id, _program_id, _parent_user_id), do: false

  @doc """
  Is this thread between two of the provider's own people (owner and/or staff)?

  Exists for the standing monitoring disclosure, which is written for a thread with
  a parent on one side. On an internal thread it would tell a provider owner that
  "the activity provider" may review their own message, and invoke child
  safeguarding over a thread containing no child.

  Classified here rather than in the web layer so the rule stays beside
  `provider_relation/2`, the primitive the compose gate and sender attribution
  already share.
  """
  @spec internal_conversation?(Conversation.t()) :: boolean()
  defdelegate internal_conversation?(conversation), to: Authorization

  @doc """
  The same question for two users, for the compose screen — where the thread does
  not exist yet but the pair about to be written is known.
  """
  @spec internal_pair?(String.t(), String.t() | nil, String.t() | nil) :: boolean()
  defdelegate internal_pair?(provider_id, user_a_id, user_b_id), to: Authorization

  @doc """
  The provider a scope acts for — its own profile, or the one employing it.

  A staff scope carries no `:provider`; the employer lives on `:staff_member`, and
  only the staff dashboard used to know that. Comparing this against the provider a
  request names is what stops a staff member composing for someone else's provider.
  """
  @spec acting_provider_id(map()) :: String.t() | nil
  def acting_provider_id(%{provider: %{id: id}}), do: id
  def acting_provider_id(%{staff_member: %{provider_id: id}}), do: id
  def acting_provider_id(_scope), do: nil

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

      Messaging.send_message(conversation_id, sender_id, "Hello!")
      #=> {:ok, %Message{content: "Hello!", ...}}

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

      Messaging.mark_as_read(conversation_id, user_id)
      #=> {:ok, %Participant{last_read_at: ~U[...], ...}}

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
  - `{:error, :not_found}` - Program missing, not owned by the acting provider,
    or the scope isn't authorised to act as that provider
  - `{:error, :not_entitled}` - Provider cannot send broadcasts
  - `{:error, :no_enrollments}` - No enrolled parents

  ## Examples

      Messaging.broadcast_to_program(scope, program_id, "Important update!")
      #=> {:ok, %Conversation{type: :program_broadcast}, %Message{}, 15}

  """
  @spec broadcast_to_program(Scope.t(), String.t(), String.t(), keyword()) ::
          {:ok, Conversation.t(), Message.t(), non_neg_integer()}
          | {:error, :not_found | :not_entitled | :no_enrollments | term()}
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

      Messaging.reply_privately_to_broadcast(scope, broadcast_id)
      #=> {:ok, "direct-conversation-uuid"}

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

      Messaging.anonymize_data_for_user(user_id)
      #=> {:ok, %{messages_anonymized: 5, participants_updated: 2}}

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

      Messaging.receive_inbound_email(%{resend_id: "...", from_address: "sender@example.com", ...})
      #=> {:ok, %InboundEmail{}}

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
          {:ok, InboundEmail.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_inbound_email_content(id, attrs) do
    context_span entity: "inbound_email" do
      case Repo.get(InboundEmail, id) do
        nil ->
          {:error, :not_found}

        email ->
          email
          |> InboundEmail.content_changeset(attrs)
          |> Repo.update()
      end
    end
  end

  @doc """
  Updates the status of an inbound email.

  ## Parameters
  - `id` - The email ID
  - `status` - The new status ("unread", "read", "archived" — atom or string)
  - `attrs` - Additional attributes to update (e.g. `read_by_id`, `read_at`)

  ## Returns
  - `{:ok, email}` - Updated email
  - `{:error, reason}` - Failure
  """
  @spec update_inbound_email_status(String.t(), String.t() | atom(), map()) ::
          {:ok, InboundEmail.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_inbound_email_status(id, status, attrs \\ %{}) do
    context_span entity: "inbound_email" do
      case Repo.get(InboundEmail, id) do
        nil ->
          {:error, :not_found}

        email ->
          email
          |> InboundEmail.status_changeset(Map.put(attrs, :status, status))
          |> Repo.update()
      end
    end
  end

  @doc """
  Subscribes to real-time updates for a conversation.

  ## Examples

      Messaging.subscribe_to_conversation(conversation_id)
      #=> :ok

  """
  @spec subscribe_to_conversation(String.t()) :: :ok | {:error, term()}
  def subscribe_to_conversation(conversation_id) do
    Phoenix.PubSub.subscribe(KlassHero.PubSub, conversation_topic(conversation_id))
  end

  @doc """
  Subscribes to real-time updates for a user's messages.

  ## Examples

      Messaging.subscribe_to_user_messages(user_id)
      #=> :ok

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

      Messaging.get_conversation(conversation_id, user_id)
      #=> {:ok, %{conversation: %Conversation{}, messages: [...], has_more: false, sender_names: %{}}}

  """
  @spec get_conversation(String.t(), String.t(), keyword()) ::
          {:ok, map()}
          | {:error, :not_found | :not_participant}
  defdelegate get_conversation(conversation_id, user_id, opts \\ []),
    to: GetConversation,
    as: :execute

  @doc """
  Lists every conversation on the platform, for a platform admin.

  Read-only monitoring (#744). Fails closed for a non-admin scope. Unlike
  `list_conversations/2` this does not read the per-user `conversation_summaries`
  projection — an admin has no row there.

  ## Options
  `:provider_id`, `:type`, `:limit`, `:before`. See
  `KlassHero.Messaging.MonitorConversations`.
  """
  @spec monitor_conversations(Scope.t(), keyword()) ::
          {:ok, [Conversation.t()], boolean()} | {:error, :unauthorized}
  defdelegate monitor_conversations(scope, opts \\ []),
    to: MonitorConversations,
    as: :execute

  @doc """
  Reads one conversation's thread for a platform admin who is not a participant.

  Read-only monitoring (#744). Fails closed for a non-admin scope. Deliberately has
  no `:mark_as_read` option: `last_read_at` feeds every unread read in the context —
  the nav total, the per-card badge and the in-thread count — and an admin viewing a
  thread must not disturb any of them.
  """
  @spec get_monitored_conversation(Scope.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, :unauthorized | :not_found}
  defdelegate get_monitored_conversation(scope, conversation_id, opts \\ []),
    to: GetMonitoredConversation,
    as: :execute

  @doc """
  Lists conversations the calling provider owns but is not a participant of.

  The threads their staff conduct with parents (#746). Owner-only: fails closed
  unless `scope.provider` is set, and never accepts a staff scope, so one staff
  member cannot read another's threads with parents. Threads the owner *is* in are
  excluded — those already appear in their own inbox via `list_conversations/2`.

  Rows come back as `KlassHero.Messaging.StaffConversation`, field-shaped to render
  through the same inbox card as the participant list.

  ## Options
  `:type`, `:limit`, `:before`. See `KlassHero.Messaging.ListStaffConversations`.
  """
  @spec list_staff_conversations(Scope.t(), keyword()) ::
          {:ok, [StaffConversation.t()], boolean()} | {:error, :unauthorized}
  defdelegate list_staff_conversations(scope, opts \\ []),
    to: ListStaffConversations,
    as: :execute

  @doc """
  Reads one staff-conducted thread for the provider owner whose business owns it.

  Owner-only (#746). A conversation belonging to another provider returns
  `:not_found`, indistinguishable from one that never existed, so a pasted id
  discloses nothing. Deliberately has no `:mark_as_read` option, for the same reason
  `get_monitored_conversation/3` has none.
  """
  @spec get_staff_conversation(Scope.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, :unauthorized | :not_found}
  defdelegate get_staff_conversation(scope, conversation_id, opts \\ []),
    to: GetStaffConversation,
    as: :execute

  @doc """
  Gets the total unread message count across all conversations for a user.

  This is useful for displaying an unread badge in the navigation.

  ## Parameters
  - user_id: The user to get unread count for

  ## Returns
  - Non-negative integer count of unread messages

  ## Examples

      Messaging.get_total_unread_count(user_id)
      #=> 5

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
  - `:before` - Cursor: only emails received before this timestamp

  ## Returns
  - `{:ok, emails, has_more}` - List of inbound emails with pagination flag
  """
  @spec list_inbound_emails(keyword()) :: {:ok, [InboundEmail.t()], boolean()}
  def list_inbound_emails(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    status = Keyword.get(opts, :status)

    # Fetch limit+1 to detect a next page without a separate COUNT query.
    results =
      InboundEmailQueries.base()
      |> InboundEmailQueries.by_status(status)
      |> InboundEmailQueries.order_by_newest()
      |> InboundEmailQueries.paginate(opts)
      |> Repo.all()

    {:ok, Enum.take(results, limit), length(results) > limit}
  end

  @doc """
  Retrieves an inbound email by ID, optionally marking it as read.

  ## Options
  - `:mark_read` - Whether to mark the email as read (default false)
  - `:reader_id` - The ID of the user reading the email

  ## Returns
  - `{:ok, email}` - The inbound email
  - `{:error, :not_found}` - Email not found
  """
  @spec get_inbound_email(String.t(), keyword()) :: {:ok, InboundEmail.t()} | {:error, :not_found}
  defdelegate get_inbound_email(id, opts \\ []), to: GetInboundEmail, as: :execute

  @doc """
  Lists all email replies for a given inbound email, oldest first.
  """
  @spec list_email_replies(String.t()) :: {:ok, [EmailReply.t()]}
  def list_email_replies(inbound_email_id) do
    # Secondary sort by id keeps ordering deterministic when timestamps collide.
    replies =
      from(r in EmailReply,
        where: r.inbound_email_id == ^inbound_email_id,
        order_by: [asc: r.inserted_at, asc: r.id]
      )
      |> Repo.all()

    {:ok, replies}
  end

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

      Messaging.count_inbound_emails_by_status(:unread)
      #=> 3

  """
  @spec count_inbound_emails_by_status(atom()) :: non_neg_integer()
  def count_inbound_emails_by_status(status) do
    status
    |> InboundEmailQueries.count_by_status()
    |> Repo.one()
    |> Kernel.||(0)
  end

  ## Inbound email persistence (called by the email use cases + workers)

  @doc "Stores a newly received inbound email (called by ReceiveInboundEmail)."
  @spec create_inbound_email(map()) :: {:ok, InboundEmail.t()} | {:error, Ecto.Changeset.t()}
  def create_inbound_email(attrs) do
    context_span entity: "inbound_email" do
      %InboundEmail{}
      |> InboundEmail.create_changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc "Fetches an inbound email by id."
  @spec get_inbound_email_by_id(String.t()) :: {:ok, InboundEmail.t()} | {:error, :not_found}
  def get_inbound_email_by_id(id) do
    case Repo.get(InboundEmail, id) do
      nil -> {:error, :not_found}
      email -> {:ok, email}
    end
  end

  @doc "Fetches an inbound email by its Resend webhook id (dedup lookup)."
  @spec get_inbound_email_by_resend_id(String.t()) ::
          {:ok, InboundEmail.t()} | {:error, :not_found}
  def get_inbound_email_by_resend_id(resend_id) do
    case Repo.get_by(InboundEmail, resend_id: resend_id) do
      nil -> {:error, :not_found}
      email -> {:ok, email}
    end
  end

  @doc """
  Marks an inbound email as read by the given reader.

  Idempotent: an already-read or archived email is returned unchanged with no
  DB write. Only an unread email is transitioned to `:read` (stamping
  `read_by_id`/`read_at`).
  """
  @spec mark_inbound_email_read(InboundEmail.t(), String.t()) ::
          {:ok, InboundEmail.t()} | {:error, Ecto.Changeset.t()}
  def mark_inbound_email_read(%InboundEmail{status: status} = email, _reader_id) when status in [:read, :archived],
    do: {:ok, email}

  def mark_inbound_email_read(%InboundEmail{} = email, reader_id) do
    context_span entity: "inbound_email" do
      email
      |> InboundEmail.status_changeset(%{
        status: :read,
        read_by_id: reader_id,
        read_at: DateTime.utc_now()
      })
      |> Repo.update()
    end
  end

  ## Email reply persistence (called by ReplyToEmail + SendEmailReplyWorker)

  @doc "Creates an email reply row (defaults to :sending)."
  @spec create_email_reply(map()) :: {:ok, EmailReply.t()} | {:error, Ecto.Changeset.t()}
  def create_email_reply(attrs) do
    context_span entity: "email_reply" do
      %EmailReply{}
      |> EmailReply.create_changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc "Fetches an email reply by id."
  @spec get_email_reply_by_id(String.t()) :: {:ok, EmailReply.t()} | {:error, :not_found}
  def get_email_reply_by_id(id) do
    case Repo.get(EmailReply, id) do
      nil -> {:error, :not_found}
      reply -> {:ok, reply}
    end
  end

  @doc "Transitions an email reply's delivery status (:sent / :failed)."
  @spec update_email_reply_status(String.t(), String.t() | atom(), map()) ::
          {:ok, EmailReply.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_email_reply_status(id, status, attrs \\ %{}) do
    context_span entity: "email_reply" do
      case Repo.get(EmailReply, id) do
        nil ->
          {:error, :not_found}

        reply ->
          reply
          |> EmailReply.status_changeset(Map.put(attrs, :status, status))
          |> Repo.update()
      end
    end
  end

  @doc """
  Returns the display name for a user.

  Used by LiveView helpers to resolve sender names for real-time messages.
  """
  @spec get_display_name(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  defdelegate get_display_name(user_id), to: KlassHero.Accounts

  @doc """
  Returns the user IDs entitled to a program's conversations, read from
  Provider (#1321) rather than from a mirror Messaging maintained itself. That
  mirror had no projection, bootstrap or rebuild, so only an event could ever
  correct it — and #1309, #1312 and #1320 were all drift between it and this
  source.

  Access-granting, and only that: `AddAssignedStaff` seeds these users as
  participants when a conversation is created, and `StaffAssignmentHandler` asks
  the same question again before evicting anyone. The render path used to share it
  to decide which senders show branded attribution, which is how deactivating a
  staff member restyled every message they had ever sent (#1348) — attribution now
  comes from `messages.sender_role`, so a change here can no longer reach the past.

  Named for entitlement rather than for the program roster because since #784 it is
  wider than one: Provider unions the roster with anyone overriding one of the
  program's sessions.
  """
  @spec get_conversation_staff_user_ids(String.t()) :: [String.t()]
  def get_conversation_staff_user_ids(program_id) do
    acl_span source: "messaging", target: "provider" do
      KlassHero.Provider.list_conversation_staff_user_ids_for_program(program_id)
    end
  end

  @doc """
  User IDs of everyone who has ever been staff at the provider.

  Renders attribution for messages predating `messages.sender_role` (#1348) and
  nothing else — it must never gate access, because it deliberately includes people
  whose employment has ended.
  """
  @spec get_provider_staff_user_ids(String.t()) :: [String.t()]
  def get_provider_staff_user_ids(provider_id) do
    acl_span source: "messaging", target: "provider" do
      KlassHero.Provider.list_staff_user_ids_for_provider(provider_id)
    end
  end

  @doc """
  Returns the PubSub topic for a conversation.

  Used by LiveViews to subscribe to real-time updates for a specific conversation.
  """
  @spec conversation_topic(String.t()) :: String.t()
  defdelegate conversation_topic(conversation_id), to: Notifications

  @doc """
  Returns the PubSub topic for a user's message notifications.

  Used by LiveViews to subscribe to new conversation and message notifications.
  """
  @spec user_messages_topic(String.t()) :: String.t()
  defdelegate user_messages_topic(user_id), to: Notifications

  # === Persistence — conversations ===

  @doc "Creates a conversation. Rewrites the broadcast-uniqueness error to `:duplicate_broadcast`."
  @spec create_conversation(map()) ::
          {:ok, Conversation.t()} | {:error, :duplicate_broadcast | Ecto.Changeset.t()}
  def create_conversation(attrs) do
    context_span entity: "conversation" do
      create_attrs =
        Map.take(attrs, [
          :type,
          :provider_id,
          :program_id,
          :subject,
          :principal_a_id,
          :principal_b_id
        ])

      %Conversation{}
      |> Conversation.create_changeset(create_attrs)
      |> Repo.insert()
      |> case do
        {:ok, conversation} ->
          Logger.debug("Created conversation", conversation_id: conversation.id, type: conversation.type)
          {:ok, conversation}

        {:error, %Ecto.Changeset{errors: errors}} = result ->
          if Keyword.has_key?(errors, :program_id), do: {:error, :duplicate_broadcast}, else: result
      end
    end
  end

  @doc "Hard-deletes archived conversations whose retention window expired before `before`."
  @spec delete_expired_conversations(DateTime.t()) :: {:ok, non_neg_integer()}
  def delete_expired_conversations(before) do
    context_span entity: "conversation" do
      {count, _} =
        ConversationQueries.base()
        |> ConversationQueries.archived_only()
        |> ConversationQueries.retention_expired(before)
        |> Repo.delete_all()

      Logger.info("Deleted expired conversations", count: count)
      {:ok, count}
    end
  end

  @doc """
  Archives conversations for programs that ended before `cutoff_date`.

  Returns the `archived_at` it wrote so the caller can put it on the
  `conversations_archived` event: the read-side projection stores that timestamp
  verbatim, and re-deriving it there would drift from the write table.
  """
  @spec archive_ended_program_conversations(DateTime.t(), non_neg_integer()) ::
          {:ok,
           %{
             count: non_neg_integer(),
             conversation_ids: [String.t()],
             archived_at: DateTime.t() | nil
           }}
  def archive_ended_program_conversations(cutoff_date, retention_days) do
    context_span entity: "conversation" do
      # Truncated because both `conversations.archived_at` and the read table's column are
      # `:utc_datetime` — keeping microseconds here would make the value on the event differ
      # from the value in the row it describes.
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      retention_until = DateTime.add(now, retention_days, :day)

      conversation_ids =
        ConversationQueries.base()
        |> ConversationQueries.with_ended_program(cutoff_date)
        |> ConversationQueries.select_ids()
        |> Repo.all()

      if conversation_ids == [] do
        {:ok, %{count: 0, conversation_ids: [], archived_at: nil}}
      else
        {count, _} =
          from(c in Conversation, where: c.id in ^conversation_ids)
          |> Repo.update_all(set: [archived_at: now, retention_until: retention_until])

        Logger.info("Archived conversations for ended programs",
          count: count,
          cutoff_date: cutoff_date,
          retention_days: retention_days
        )

        {:ok, %{count: count, conversation_ids: conversation_ids, archived_at: now}}
      end
    end
  end

  @doc "Fetches a conversation by id. `opts[:preload]` preloads associations."
  @spec get_conversation_by_id(String.t(), keyword()) ::
          {:ok, Conversation.t()} | {:error, :not_found}
  def get_conversation_by_id(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    ConversationQueries.base()
    |> ConversationQueries.by_id(id)
    |> ConversationQueries.preload_assocs(preloads)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      conversation -> {:ok, conversation}
    end
  end

  @doc "Finds the direct conversation between two users at a provider, if any."
  @spec find_direct_conversation(String.t(), String.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, :not_found}
  def find_direct_conversation(provider_id, user_id_1, user_id_2) do
    ConversationQueries.find_direct(provider_id, user_id_1, user_id_2)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      conversation -> {:ok, conversation}
    end
  end

  @doc "Finds the active broadcast conversation for a program, if any."
  @spec find_active_broadcast_for_program(String.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, :not_found}
  def find_active_broadcast_for_program(provider_id, program_id) do
    ConversationQueries.base()
    |> ConversationQueries.by_provider(provider_id)
    |> ConversationQueries.by_type(:program_broadcast)
    |> ConversationQueries.active_only()
    |> ConversationQueries.by_program(program_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      conversation -> {:ok, conversation}
    end
  end

  @doc """
  Ids of active program conversations the user is NOT a participant of.

  **Staff only.** "Program conversation" means every type scoped to the program, and a
  `:direct` parent↔provider conversation carries a `program_id` too
  (`CreateDirectConversation`, when given one). Back-filling a *parent* from this list would seat a
  newly enrolled family in every other family's private thread. Staff legitimately
  belong in both kinds, which is what makes the width correct for them and only them;
  parents get `list_active_broadcast_ids_without_participant/2`.
  """
  @spec list_active_program_conversation_ids_without_participant(String.t(), String.t()) :: [String.t()]
  def list_active_program_conversation_ids_without_participant(program_id, user_id) do
    ConversationQueries.base()
    |> ConversationQueries.by_program(program_id)
    |> ConversationQueries.active_only()
    |> ConversationQueries.where_user_is_not_participant(user_id)
    |> ConversationQueries.select_ids()
    |> Repo.all()
  end

  @doc """
  Ids of the program's active *broadcast* conversations the user is NOT a participant of.

  The parent-safe counterpart to
  `list_active_program_conversation_ids_without_participant/2`, which must not be
  reused here — see its doc for the privacy trap the `:program_broadcast` filter
  closes. The two cannot be folded together.
  """
  @spec list_active_broadcast_ids_without_participant(String.t(), String.t()) :: [String.t()]
  def list_active_broadcast_ids_without_participant(program_id, user_id) do
    ConversationQueries.base()
    |> ConversationQueries.by_program(program_id)
    |> ConversationQueries.by_type(:program_broadcast)
    |> ConversationQueries.active_only()
    |> ConversationQueries.where_user_is_not_participant(user_id)
    |> ConversationQueries.select_ids()
    |> Repo.all()
  end

  @doc """
  Ids of active program conversations the user IS a participant of.

  Every type, `:direct` included — see
  `list_active_program_conversation_ids_without_participant/2` for why that matters.
  """
  @spec list_active_program_conversation_ids_with_participant(String.t(), String.t()) :: [String.t()]
  def list_active_program_conversation_ids_with_participant(program_id, user_id) do
    ConversationQueries.base()
    |> ConversationQueries.by_program(program_id)
    |> ConversationQueries.active_only()
    |> ConversationQueries.where_user_is_participant(user_id)
    |> ConversationQueries.select_ids()
    |> Repo.all()
  end

  @doc "Ids of archived conversations whose retention window expired before `before`."
  @spec list_expired_conversation_ids(DateTime.t()) :: [String.t()]
  def list_expired_conversation_ids(before) do
    ConversationQueries.base()
    |> ConversationQueries.archived_only()
    |> ConversationQueries.retention_expired(before)
    |> ConversationQueries.select_ids()
    |> Repo.all()
  end

  # === Reads — the inbox ===

  @doc """
  Lists a user's non-archived conversations, newest message first. Limit+1 paginated.

  Read live from the write model (ADR-0023) and returned as `InboxConversation`
  structs, which carry the field names `MessagingComponents.conversation_card/1`
  renders — the same shape `ListStaffConversations` returns, which is why one
  component serves both inboxes.

  A conversation with no message does not appear: the page query's lateral join onto
  the newest message is INNER.

  ## Examples

      Messaging.list_conversations(user_id)
      #=> {:ok, [%InboxConversation{conversation_id: "…", unread_count: 2}], false}

  """
  @spec list_conversations(String.t(), keyword()) ::
          {:ok, [InboxConversation.t()], boolean()}
  defdelegate list_conversations(user_id, opts \\ []), to: ListConversations, as: :execute

  @doc "True if the conversation already carries a system message stamped with this token."
  @spec has_system_note?(String.t(), String.t()) :: boolean()
  def has_system_note?(conversation_id, token) do
    # The system message *is* the record — its content is "<token> Re: <subject>",
    # so there is nothing to denormalise and nothing to keep in sync. Served by
    # the (conversation_id, inserted_at) index, and bounded by one conversation,
    # which is what #431 needed when the old check scanned only 100 messages.
    #
    # Not filtered on deleted_at, deliberately: a note whose message was later
    # soft-deleted still counts as posted, so a second tap must not re-add it.
    from(m in Message,
      where:
        m.conversation_id == ^conversation_id and m.message_type == :system and
          like(m.content, ^(token <> "%"))
    )
    |> Repo.exists?()
  end

  # === Persistence — messages ===

  @doc "Creates a message. Content-or-attachments is enforced by the caller (send_message)."
  @spec create_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def create_message(attrs) do
    context_span entity: "message" do
      create_attrs =
        Map.take(attrs, [:conversation_id, :sender_id, :sender_role, :content, :message_type])

      %Message{}
      |> Message.create_changeset(create_attrs)
      |> Repo.insert()
      |> case do
        {:ok, message} ->
          Logger.debug("Created message", message_id: message.id, conversation_id: message.conversation_id)
          {:ok, message}

        error ->
          error
      end
    end
  end

  @doc "Soft-deletes a message by setting `deleted_at`."
  @spec soft_delete_message(Message.t()) ::
          {:ok, Message.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def soft_delete_message(message) do
    context_span entity: "message" do
      case Repo.get(Message, message.id) do
        nil ->
          {:error, :not_found}

        schema ->
          schema
          |> Message.delete_changeset(%{deleted_at: DateTime.utc_now()})
          |> Repo.update()
          |> case do
            {:ok, updated} ->
              Logger.info("Soft deleted message", message_id: message.id)
              {:ok, updated}

            error ->
              error
          end
      end
    end
  end

  @doc "Blanks the content of all messages by a sender (GDPR anonymization)."
  @spec anonymize_messages_for_sender(String.t()) ::
          {:ok, non_neg_integer()} | {:error, :database_connection_error | :database_query_error}
  def anonymize_messages_for_sender(sender_id) do
    context_span entity: "message" do
      {count, _} =
        from(m in Message, where: m.sender_id == ^sender_id)
        |> Repo.update_all(set: [content: "[deleted]"])

      Logger.debug("Anonymized messages for sender", sender_id: sender_id, count: count)
      {:ok, count}
    end
  rescue
    e in DBConnection.ConnectionError ->
      Logger.error("Database connection error anonymizing messages for sender",
        sender_id: sender_id,
        error: Exception.message(e)
      )

      {:error, :database_connection_error}

    e in Postgrex.Error ->
      Logger.error("Database query error anonymizing messages for sender",
        sender_id: sender_id,
        error: Exception.message(e)
      )

      {:error, :database_query_error}
  end

  @doc "Hard-deletes all messages belonging to conversations whose retention expired before `before`."
  @spec delete_messages_for_expired_conversations(DateTime.t()) ::
          {:ok, non_neg_integer(), [String.t()]}
  def delete_messages_for_expired_conversations(before) do
    context_span entity: "message" do
      expired_conversation_ids =
        from(c in Conversation,
          where: not is_nil(c.retention_until) and c.retention_until < ^before,
          select: c.id
        )
        |> Repo.all()

      if expired_conversation_ids == [] do
        {:ok, 0, []}
      else
        {count, _} =
          from(m in Message, where: m.conversation_id in ^expired_conversation_ids)
          |> Repo.delete_all()

        Logger.info("Deleted messages for expired conversations",
          count: count,
          conversation_count: length(expired_conversation_ids)
        )

        {:ok, count, expired_conversation_ids}
      end
    end
  end

  @doc "Fetches a message by id, with its attachments."
  @spec get_message_by_id(String.t()) :: {:ok, Message.t()} | {:error, :not_found}
  def get_message_by_id(id) do
    MessageQueries.base()
    |> MessageQueries.by_id(id)
    |> MessageQueries.preload_assocs([:attachments])
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      message -> {:ok, message}
    end
  end

  @doc "Lists a conversation's non-deleted messages, newest first, with attachments. Limit+1 paginated."
  @spec list_messages_for_conversation(String.t(), keyword()) :: {:ok, [Message.t()], boolean()}
  def list_messages_for_conversation(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    results =
      MessageQueries.base()
      |> MessageQueries.by_conversation(conversation_id)
      |> MessageQueries.not_deleted()
      |> MessageQueries.order_by_newest()
      |> MessageQueries.paginate(opts)
      |> MessageQueries.preload_assocs([:attachments])
      |> Repo.all()

    {:ok, Enum.take(results, limit), length(results) > limit}
  end

  @doc """
  Lists messages with their attachments plus a sender_id => display-name map.

  Returns `{:ok, messages, sender_names, has_more}`.
  """
  @spec list_messages_with_senders(String.t(), keyword()) ::
          {:ok, [Message.t()], %{String.t() => String.t()}, boolean()}
  def list_messages_with_senders(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    results =
      MessageQueries.base()
      |> MessageQueries.by_conversation(conversation_id)
      |> MessageQueries.not_deleted()
      |> MessageQueries.order_by_newest()
      |> MessageQueries.paginate(opts)
      |> MessageQueries.preload_assocs([:attachments])
      |> Repo.all()

    messages = Enum.take(results, limit)
    {:ok, messages, build_sender_names_map(messages), length(results) > limit}
  end

  @doc "Fetches the latest non-deleted message in a conversation."
  @spec get_latest_message(String.t()) :: {:ok, Message.t()} | {:error, :not_found}
  def get_latest_message(conversation_id) do
    MessageQueries.latest_for_conversation(conversation_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      message -> {:ok, message}
    end
  end

  @doc "Counts unread (non-deleted) messages in a conversation after `last_read_at`."
  @spec count_unread_messages(String.t(), DateTime.t() | nil) :: non_neg_integer()
  def count_unread_messages(conversation_id, last_read_at) do
    MessageQueries.count_unread(conversation_id, last_read_at)
    |> Repo.one()
    |> Kernel.||(0)
  end

  # Builds a sender_id => display-name map. Ids Accounts cannot resolve are
  # omitted rather than raising, so a dangling correlation id degrades to
  # "Unknown" at the call site instead of failing the whole page.
  defp build_sender_names_map(messages) do
    messages
    |> Enum.map(& &1.sender_id)
    |> Enum.uniq()
    |> Accounts.get_display_names()
  end

  # === Persistence — participants ===

  @doc """
  Adds a participant to a conversation. Defaults `joined_at` to now.

  Seats them with their read cursor at whatever the conversation already contained —
  the same rule as the two batch functions, see `seating_cursors/1`. Today's callers
  all seat into a conversation their own transaction just created, so the cursor is
  `nil` for them either way; it is applied here so that a caller adding someone to a
  *populated* conversation cannot silently reintroduce #381. An explicit
  `:last_read_at` in `attrs` still wins.
  """
  @spec add_participant(map()) ::
          {:ok, Participant.t()} | {:error, :already_participant | Ecto.Changeset.t()}
  def add_participant(attrs) do
    context_span entity: "participant" do
      cursor = Map.get(seating_cursors([attrs.conversation_id]), attrs.conversation_id)

      attrs =
        attrs
        |> Map.put_new(:joined_at, DateTime.utc_now())
        |> Map.put_new(:last_read_at, cursor)

      %Participant{}
      |> Participant.create_changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, participant} ->
          Logger.debug("Added participant",
            participant_id: participant.id,
            conversation_id: participant.conversation_id,
            user_id: participant.user_id
          )

          {:ok, participant}

        {:error, %Ecto.Changeset{} = changeset} = result ->
          case changeset.errors[:conversation_id] do
            {"has already been taken", _} -> {:error, :already_participant}
            _ -> result
          end
      end
    end
  end

  @doc "Marks a participant's messages as read up to `read_at`."
  @spec mark_participant_read(String.t(), String.t(), DateTime.t()) ::
          {:ok, Participant.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def mark_participant_read(conversation_id, user_id, read_at) do
    context_span entity: "participant" do
      from(p in Participant,
        where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
      )
      |> Repo.one()
      |> case do
        nil ->
          {:error, :not_found}

        participant ->
          participant
          |> Participant.mark_read_changeset(%{last_read_at: read_at})
          |> Repo.update()
          |> case do
            {:ok, updated} ->
              Logger.debug("Marked as read",
                conversation_id: conversation_id,
                user_id: user_id,
                read_at: read_at
              )

              {:ok, updated}

            error ->
              error
          end
      end
    end
  end

  @doc "Removes a participant from a conversation by setting `left_at`."
  @spec leave_conversation(String.t(), String.t()) ::
          {:ok, Participant.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def leave_conversation(conversation_id, user_id) do
    context_span entity: "participant" do
      now = DateTime.utc_now()

      from(p in Participant,
        where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
      )
      |> Repo.one()
      |> case do
        nil ->
          {:error, :not_found}

        participant ->
          participant
          |> Participant.leave_changeset(%{left_at: now})
          |> Repo.update()
          |> case do
            {:ok, updated} ->
              Logger.info("Participant left conversation",
                conversation_id: conversation_id,
                user_id: user_id
              )

              {:ok, updated}

            error ->
              error
          end
      end
    end
  end

  @doc "Marks all active participations for a user as left (GDPR path)."
  @spec mark_all_participations_left(String.t()) ::
          {:ok, non_neg_integer()}
          | {:error, :database_connection_error | :database_query_error}
  def mark_all_participations_left(user_id) do
    context_span entity: "participant" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {count, _} =
        from(p in Participant, where: p.user_id == ^user_id and is_nil(p.left_at))
        |> Repo.update_all(set: [left_at: now])

      Logger.debug("Marked all participations as left for user", user_id: user_id, count: count)

      {:ok, count}
    end
  rescue
    e in DBConnection.ConnectionError ->
      Logger.error("Database connection error marking participations as left",
        user_id: user_id,
        error: Exception.message(e)
      )

      {:error, :database_connection_error}

    e in Postgrex.Error ->
      Logger.error("Database query error marking participations as left",
        user_id: user_id,
        error: Exception.message(e)
      )

      {:error, :database_query_error}
  end

  @doc """
  Adds a batch of users as participants of a conversation (skips existing).

  Seats them with their read cursor at whatever the conversation already contained,
  so anything said before they arrived is history rather than a notification. See
  `seating_cursors/1`.
  """
  @spec add_participants(String.t(), [String.t()]) :: {:ok, [Participant.t()]}
  def add_participants(conversation_id, user_ids) do
    context_span entity: "participant" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      cursor = Map.get(seating_cursors([conversation_id]), conversation_id)

      entries =
        Enum.map(user_ids, fn user_id ->
          %{
            id: Ecto.UUID.generate(),
            conversation_id: conversation_id,
            user_id: user_id,
            last_read_at: cursor,
            joined_at: now,
            inserted_at: now,
            updated_at: now
          }
        end)

      {_count, participants} =
        Repo.insert_all(Participant, entries,
          returning: true,
          on_conflict: :nothing,
          conflict_target: [:conversation_id, :user_id]
        )

      Logger.debug("Added batch of participants",
        conversation_id: conversation_id,
        count: length(participants)
      )

      {:ok, participants}
    end
  end

  @doc """
  Adds a user to a batch of conversations, re-activating any they had left.

  Each conversation gets its own read cursor — see `seating_cursors/1`.
  """
  @spec add_user_to_conversations(String.t(), [String.t()]) :: {:ok, non_neg_integer()}
  def add_user_to_conversations(_user_id, []), do: {:ok, 0}

  def add_user_to_conversations(user_id, conversation_ids) do
    context_span entity: "participant" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      cursors = seating_cursors(conversation_ids)

      entries =
        Enum.map(conversation_ids, fn conversation_id ->
          %{
            id: Ecto.UUID.generate(),
            conversation_id: conversation_id,
            user_id: user_id,
            last_read_at: Map.get(cursors, conversation_id),
            joined_at: now,
            inserted_at: now,
            updated_at: now
          }
        end)

      {count, _} =
        Repo.insert_all(Participant, entries,
          on_conflict: participant_reactivation(),
          conflict_target: [:conversation_id, :user_id]
        )

      Logger.debug("Added user to conversations in batch",
        user_id: user_id,
        conversation_count: length(conversation_ids),
        added_count: count
      )

      {:ok, count}
    end
  end

  # `joined_at` is absent from the `set:` list deliberately: the original stays as the
  # audit trail of when this person first entered the conversation.
  #
  # The cursor is re-stamped because rejoining is joining: someone re-added to a
  # conversation was not entitled to it while they were away, so what happened in the
  # meantime is history, not a backlog. Only a soft-left row reaches this branch —
  # `where_user_is_not_participant/2` filters out active participants — so a replayed
  # event cannot use it to wipe a live participant's read state.
  defp participant_reactivation do
    from(p in Participant,
      update: [
        set: [
          left_at: nil,
          last_read_at: fragment("EXCLUDED.last_read_at"),
          updated_at: fragment("EXCLUDED.updated_at")
        ]
      ]
    )
  end

  # The read cursor someone gets when they are seated into a conversation: the newest
  # message already in it, or nil when it is empty.
  #
  # Never `DateTime.utc_now/0`. `messages.inserted_at` is `:utc_datetime`, so a message
  # written in the same second would fall on the wrong side of the `>` comparison every
  # unread counter makes and be silently marked read.
  #
  # Soft-deleted messages count towards the anchor even though they are invisible: the
  # cursor must sit at or after everything already in the conversation, or a newcomer
  # gets badged for history. See `MessageQueries.newest_inserted_at_by_conversation/1`.
  defp seating_cursors(conversation_ids) do
    conversation_ids
    |> MessageQueries.newest_inserted_at_by_conversation()
    |> Repo.all()
    |> Map.new()
  end

  @doc "Fetches a participant by conversation and user."
  @spec get_participant(String.t(), String.t()) :: {:ok, Participant.t()} | {:error, :not_found}
  def get_participant(conversation_id, user_id) do
    from(p in Participant, where: p.conversation_id == ^conversation_id and p.user_id == ^user_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      participant -> {:ok, participant}
    end
  end

  @doc "Lists active participants of a conversation, oldest join first."
  @spec list_participants(String.t()) :: [Participant.t()]
  def list_participants(conversation_id) do
    from(p in Participant,
      where: p.conversation_id == ^conversation_id and is_nil(p.left_at),
      order_by: [asc: p.joined_at]
    )
    |> Repo.all()
  end

  @doc "True if the user is an active participant of the conversation."
  @spec participant?(String.t(), String.t()) :: boolean()
  def participant?(conversation_id, user_id) do
    from(p in Participant,
      where: p.conversation_id == ^conversation_id and p.user_id == ^user_id and is_nil(p.left_at)
    )
    |> Repo.exists?()
  end

  # === Persistence — attachments ===

  @doc "Bulk-inserts message attachments."
  @spec create_attachments([map()]) ::
          {:ok, [Attachment.t()]} | {:error, :attachment_insert_failed}
  def create_attachments([]), do: {:ok, []}

  def create_attachments(attrs_list) do
    context_span entity: "attachment" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      entries =
        Enum.map(attrs_list, fn attrs ->
          attrs
          |> Map.take([
            :message_id,
            :file_url,
            :storage_path,
            :original_filename,
            :content_type,
            :file_size_bytes
          ])
          |> Map.merge(%{id: Ecto.UUID.generate(), inserted_at: now, updated_at: now})
        end)

      {count, attachments} = Repo.insert_all(Attachment, entries, returning: true)

      Logger.debug("Bulk-inserted attachments", count: count)

      {:ok, attachments}
    end
  rescue
    e in [Ecto.ConstraintError, Postgrex.Error] ->
      Logger.error("Failed to bulk-insert attachments",
        count: length(attrs_list),
        error: Exception.message(e)
      )

      {:error, :attachment_insert_failed}
  end

  @doc "Lists attachments for a message, oldest first."
  @spec list_attachments_for_message(String.t()) :: [Attachment.t()]
  def list_attachments_for_message(message_id) do
    from(a in Attachment, where: a.message_id == ^message_id, order_by: [asc: a.inserted_at])
    |> Repo.all()
  end

  @doc "Lists attachments for many messages, grouped by `message_id`."
  @spec list_attachments_for_messages([String.t()]) ::
          %{optional(String.t()) => [Attachment.t()]}
  def list_attachments_for_messages([]), do: %{}

  def list_attachments_for_messages(message_ids) do
    from(a in Attachment, where: a.message_id in ^message_ids, order_by: [asc: a.inserted_at])
    |> Repo.all()
    |> Enum.group_by(& &1.message_id)
  end

  @doc "Returns storage paths for all attachments in the given conversations."
  @spec attachment_storage_paths_for_conversations([String.t()]) :: {:ok, [String.t()]}
  def attachment_storage_paths_for_conversations([]), do: {:ok, []}

  def attachment_storage_paths_for_conversations(conversation_ids) do
    paths =
      from(a in Attachment,
        join: m in Message,
        on: a.message_id == m.id,
        where: m.conversation_id in ^conversation_ids,
        select: a.storage_path
      )
      |> Repo.all()

    {:ok, paths}
  end
end
