defmodule KlassHero.Messaging.GetConversationContext do
  @moduledoc """
  Use case for fetching enriched conversation context for title display.

  Reads enrolled child names and other participant name from the
  conversation_summaries read model (CQRS read side). Used by the web layer
  to build human-readable conversation titles, e.g. "Sarah for Emma, Liam".
  """

  @doc """
  Returns enrolled child names and other participant name for a conversation/user pair.

  ## Parameters
  - conversation_id: The conversation to look up
  - user_id: The requesting user's ID (determines which summary row to read)

  ## Returns
  - Map with `:enrolled_child_names` (list of strings) and `:other_participant_name` (string or nil)
  """
  @spec execute(String.t(), String.t()) ::
          %{enrolled_child_names: [String.t()], other_participant_name: String.t() | nil}
  def execute(conversation_id, user_id) do
    KlassHero.Messaging.get_conversation_summary_context(conversation_id, user_id)
  end
end
