defmodule KlassHero.Repo.Migrations.AddActiveParticipantUserIndex do
  @moduledoc """
  Both reads that replaced the `conversation_summaries` projection start from "the
  conversations this user is still in" — `ListConversations`'s page query and
  `ConversationQueries.total_unread_count/1`. The existing
  `conversation_participants(user_id)` index serves that, but carries every row the
  user ever left; the partial form keeps only the live ones.
  """

  use Ecto.Migration

  def change do
    create index(:conversation_participants, [:user_id],
             where: "left_at IS NULL",
             name: :conversation_participants_active_user_id_index
           )
  end
end
