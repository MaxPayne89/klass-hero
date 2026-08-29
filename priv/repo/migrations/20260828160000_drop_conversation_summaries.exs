defmodule KlassHero.Repo.Migrations.DropConversationSummaries do
  @moduledoc """
  Drops the last read table Messaging owned (ADR-0023).

  Nothing reads or writes it: the projection went with the previous commit, the inbox
  and the unread badge read the write model live, and conversation titling is derived
  by `Messaging.ConversationContext`.

  `down/0` recreates it empty, with every column, index and constraint it carried at
  the end — the shape #1321 established, so a rollback restores a table the retired
  code would still compile against. It does not repopulate: only the deleted
  projection knew how, which is the point.

  ## Rollout

  Fly runs migrations as a `release_command`, before new machines take traffic, so
  this executes while the previous release is still reading the table. The parent,
  provider and staff inboxes, the nav badge and the dashboard 500 until the last old
  machine drains. Deploy at low traffic and watch `error_tracker` through the window.
  """

  use Ecto.Migration

  def up do
    drop table(:conversation_summaries)
  end

  def down do
    create table(:conversation_summaries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :conversation_id, :binary_id, null: false
      add :user_id, :binary_id, null: false
      add :conversation_type, :string, null: false
      add :provider_id, :binary_id, null: false
      add :program_id, :binary_id
      add :subject, :text
      add :other_participant_name, :text
      add :participant_count, :integer, default: 0
      add :latest_message_content, :text
      add :latest_message_sender_id, :binary_id
      add :latest_message_at, :utc_datetime
      add :unread_count, :integer, default: 0, null: false
      add :last_read_at, :utc_datetime
      add :archived_at, :utc_datetime
      add :system_notes, :map, null: false, default: %{}
      add :enrolled_child_names, {:array, :string}, default: []
      add :program_name, :text
      add :has_attachments, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:conversation_summaries, [:conversation_id, :user_id])

    create index(:conversation_summaries, [:user_id, :archived_at, :latest_message_at],
             name: :conversation_summaries_inbox_idx
           )

    create index(:conversation_summaries, [:conversation_id])

    # jsonb_ops, not jsonb_path_ops: the `?` key-exists operator the system-note lookup
    # used is not in the smaller opclass.
    create index(:conversation_summaries, [:system_notes], using: "gin")

    execute "CREATE INDEX conversation_summaries_unread_idx ON conversation_summaries (user_id) WHERE archived_at IS NULL"

    execute "ALTER TABLE conversation_summaries ADD CONSTRAINT unread_count_non_negative CHECK (unread_count >= 0)"
  end
end
