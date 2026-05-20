defmodule KlassHero.Repo.Migrations.AddProgramNameToConversationSummaries do
  use Ecto.Migration

  def up do
    alter table(:conversation_summaries) do
      add :program_name, :string
    end

    flush()

    execute("""
    UPDATE conversation_summaries cs
    SET program_name = p.title
    FROM programs p
    WHERE cs.program_id = p.id
      AND cs.conversation_type = 'program_broadcast'
      AND cs.program_name IS NULL
    """)
  end

  def down do
    alter table(:conversation_summaries) do
      remove :program_name
    end
  end
end
