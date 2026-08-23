defmodule KlassHero.Messaging.GetConversation do
  @moduledoc """
  Use case for retrieving a conversation with messages.

  This use case:
  1. Retrieves the conversation by ID
  2. Verifies the requester is a participant
  3. Loads messages with pagination
  4. Optionally marks messages as read
  5. Returns conversation with messages enriched with sender names
  """

  alias KlassHero.Messaging.Authorization
  alias KlassHero.Messaging.MarkAsRead

  require Logger

  @doc """
  Gets a conversation with its messages.

  ## Parameters
  - conversation_id: The conversation to retrieve
  - user_id: The requesting user (for access control)
  - opts: Optional parameters
    - limit: Number of messages to return (default 50)
    - before: Get messages before this timestamp
    - mark_as_read: Whether to mark messages as read (default false)

  ## Returns
  - `{:ok, result_map}` - Success, with:
    - `:conversation` - The conversation entity
    - `:messages` - List of messages with sender_name enriched
    - `:has_more` - Whether there are more messages
    - `:sender_names` - Map of sender_id => display name
  - `{:error, :not_found}` - Conversation doesn't exist
  - `{:error, :not_participant}` - User is not in the conversation
  """
  @spec execute(String.t(), String.t(), keyword()) ::
          {:ok, map()}
          | {:error, :not_found | :not_participant}
  def execute(conversation_id, user_id, opts \\ []) do
    mark_as_read? = Keyword.get(opts, :mark_as_read, false)

    with {:ok, conversation} <-
           KlassHero.Messaging.get_conversation_by_id(conversation_id, preload: [:participants]),
         :ok <- Authorization.verify_participant(conversation_id, user_id),
         {:ok, messages, sender_names, has_more} <-
           KlassHero.Messaging.list_messages_with_senders(conversation_id, opts) do
      maybe_mark_as_read(mark_as_read?, conversation_id, user_id)

      Logger.debug("Retrieved conversation",
        conversation_id: conversation_id,
        user_id: user_id,
        message_count: length(messages)
      )

      {:ok,
       %{
         conversation: conversation,
         messages: messages,
         has_more: has_more,
         sender_names: sender_names
       }}
    end
  end

  defp maybe_mark_as_read(false, _conversation_id, _user_id), do: :ok

  defp maybe_mark_as_read(true, conversation_id, user_id) do
    case MarkAsRead.execute(conversation_id, user_id) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to mark as read",
          conversation_id: conversation_id,
          user_id: user_id,
          reason: inspect(reason)
        )

        :ok
    end
  end
end
