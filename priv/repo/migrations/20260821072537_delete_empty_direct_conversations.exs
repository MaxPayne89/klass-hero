defmodule KlassHero.Repo.Migrations.DeleteEmptyDirectConversations do
  @moduledoc """
  Removes direct conversations that never carried a message (#1446).

  Compose used to create the row when the box opened, so backing out left an
  empty thread. Creation now waits for the first message; these are the rows
  that predate that.

  `conversation_participants` and `messages` cascade from `conversations`, but
  `conversation_summaries` is a read table with no foreign key — a raw delete
  reaches its projection through no event, so its rows are removed here
  explicitly or they are stranded forever.

  Broadcasts are left alone: an empty one is a provider's unsent announcement,
  not this bug.
  """

  use Ecto.Migration

  def up do
    execute("""
    DELETE FROM conversation_summaries cs
    USING conversations c
    WHERE cs.conversation_id = c.id
      AND c.type = 'direct'
      AND NOT EXISTS (SELECT 1 FROM messages m WHERE m.conversation_id = c.id)
    """)

    execute("""
    DELETE FROM conversations c
    WHERE c.type = 'direct'
      AND NOT EXISTS (SELECT 1 FROM messages m WHERE m.conversation_id = c.id)
    """)
  end

  def down do
    :ok
  end
end
