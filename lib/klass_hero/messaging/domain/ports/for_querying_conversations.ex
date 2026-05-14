defmodule KlassHero.Messaging.Domain.Ports.ForQueryingConversations do
  @moduledoc """
  Read-only port for querying conversations in the Messaging bounded context.

  Separated from `ForManagingConversations` (write-only) to support CQRS at
  the port level. Read operations never mutate state.
  """

  alias KlassHero.Messaging.Domain.Models.Conversation

  @doc """
  Retrieves a conversation by ID with optional preloads.

  Options:
  - preload: [:participants, :messages] - associations to preload

  Returns:
  - `{:ok, Conversation.t()}` - Conversation found
  - `{:error, :not_found}` - No conversation exists with the given ID
  """
  @callback get_by_id(id :: binary(), opts :: keyword()) ::
              {:ok, Conversation.t()} | {:error, :not_found}

  @doc """
  Finds an existing direct conversation between provider and user.

  Returns:
  - `{:ok, Conversation.t()}` - Existing conversation found
  - `{:error, :not_found}` - No conversation exists
  """
  @callback find_direct_conversation(provider_id :: binary(), user_id :: binary()) ::
              {:ok, Conversation.t()} | {:error, :not_found}

  @doc """
  Finds the active broadcast conversation for a specific program.

  Returns:
  - `{:ok, Conversation.t()}` - Active broadcast found
  - `{:error, :not_found}` - No active broadcast exists for this program
  """
  @callback find_active_broadcast_for_program(provider_id :: binary(), program_id :: binary()) ::
              {:ok, Conversation.t()} | {:error, :not_found}

  @doc """
  Lists all conversations for a user.

  Returns conversations where the user is an active participant,
  ordered by most recent message first.

  Options:
  - limit: integer - max results (default 50)
  - cursor: binary - pagination cursor
  """
  @callback list_for_user(user_id :: binary(), opts :: keyword()) ::
              {:ok, [Conversation.t()], has_more :: boolean()}

  @doc """
  Lists all conversations for a provider.

  Returns all conversations owned by the provider,
  ordered by most recent message first.

  Options:
  - limit: integer - max results (default 50)
  - cursor: binary - pagination cursor
  - type: :direct | :program_broadcast - filter by type
  """
  @callback list_for_provider(provider_id :: binary(), opts :: keyword()) ::
              {:ok, [Conversation.t()], has_more :: boolean()}

  @doc """
  Gets total unread count across all conversations for a user.

  Counts unread messages in active conversations where the user is a participant.
  Excludes archived conversations and conversations the user has left.

  Returns a non-negative integer count.
  """
  @callback get_total_unread_count(user_id :: binary()) :: non_neg_integer()

  @doc """
  Lists IDs of active conversations for a program where a specific user
  is NOT yet a participant.

  Used by the staff assignment handler to find conversations that need
  a newly-assigned staff member added as a participant.

  Returns a list of conversation ID strings (may be empty).
  """
  @callback list_active_program_conversation_ids_without_participant(
              program_id :: binary(),
              user_id :: binary()
            ) :: [binary()]

  @doc """
  Lists IDs of active conversations for a program where a specific user
  IS an active participant.

  Used by the staff-unassignment flow to find conversations from which a
  newly-removed staff member must be detached.

  Returns a list of conversation ID strings (may be empty).
  """
  @callback list_active_program_conversation_ids_with_participant(
              program_id :: binary(),
              user_id :: binary()
            ) :: [binary()]

  @doc """
  Lists IDs of conversations whose retention period has expired.

  Returns IDs for archived conversations where `retention_until` is
  before the given `before` datetime. Used by the retention policy to
  collect attachment URLs for S3 cleanup before the cascade delete.

  Returns a list of conversation ID strings (may be empty).
  """
  @callback list_expired_ids(before :: DateTime.t()) :: [binary()]
end
