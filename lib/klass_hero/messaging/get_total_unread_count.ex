defmodule KlassHero.Messaging.GetTotalUnreadCount do
  @moduledoc """
  The unread total behind the navigation badge.

  Read live from `conversation_participants` + `messages` via
  `KlassHero.Messaging.Queries.ConversationQueries.total_unread_count/1`, which is
  also where the predicate set is documented — it must stay identical to
  `KlassHero.Messaging.ListConversations`'s per-conversation count, since the two
  render one above the other.

  Replaces a sum over the `conversation_summaries` read table (ADR-0023). That column
  was maintained by eight event handlers and could only be corrected by a projection
  rebuild, which is how #1513 stayed wrong through several deploys.
  """

  alias KlassHero.Messaging.Queries.ConversationQueries
  alias KlassHero.Repo

  @doc "Total unread messages across the user's active, non-archived conversations."
  @spec execute(String.t()) :: non_neg_integer()
  def execute(user_id) do
    Repo.one(ConversationQueries.total_unread_count(user_id)) || 0
  end
end
