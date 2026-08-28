defmodule KlassHero.Messaging.GetConversationContext do
  @moduledoc """
  Titling context for one conversation, for the thread page's title.

  Loads the conversation with its participants and hands it to
  `ConversationContext.for_conversations/2` as a one-element list — the same
  derivation the inbox runs over a page, so a thread's title and its card can no
  longer disagree.

  It used to read a `conversation_summaries` row keyed `(conversation_id, user_id)`,
  a second implementation of a derivation `ListConversations` already did live. That
  duplication is what ADR-0023 retired projections over.
  """

  alias KlassHero.Messaging
  alias KlassHero.Messaging.ConversationContext

  @doc """
  Returns enrolled child names and other participant name for a conversation/user pair.

  Both are empty for a viewer who is neither a principal nor an active participant,
  and for a conversation that does not exist.
  """
  @spec execute(String.t(), String.t()) ::
          %{enrolled_child_names: [String.t()], other_participant_name: String.t() | nil}
  def execute(conversation_id, user_id) do
    case Messaging.get_conversation_by_id(conversation_id, preload: [:participants]) do
      {:ok, conversation} ->
        conversation
        |> List.wrap()
        |> ConversationContext.for_conversations(user_id)
        |> Map.fetch!(conversation.id)

      {:error, :not_found} ->
        %{enrolled_child_names: [], other_participant_name: nil}
    end
  end
end
