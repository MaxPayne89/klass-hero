defmodule KlassHero.Repo.Migrations.RenameBehavioralNotesToSessionNotes do
  @moduledoc """
  Renames `behavioral_notes` to `session_notes` (#924), along with every index
  and constraint whose name was derived from the old table name.

  Renaming the indexes and constraints is not cosmetic. `ALTER TABLE ... RENAME
  TO` moves the table only — Postgres leaves every dependent object under its
  original name. Ecto, meanwhile, infers constraint names from the schema's
  `source` at runtime and matches them exactly, so once `SessionNote` declares
  `schema "session_notes"`, `foreign_key_constraint(:child_id)` starts looking
  for `session_notes_child_id_fkey`. If the constraint were still named
  `behavioral_notes_child_id_fkey` the match would fail and the violation would
  surface as a raised `Postgrex.Error` instead of `{:error, changeset}`.

  The renames are catalog-driven rather than a hardcoded list: not-null
  constraints only exist as `pg_constraint` rows on PostgreSQL 17+, so an
  explicit `RENAME CONSTRAINT ..._not_null` would fail on an older server.
  Looping over what is actually there is version-agnostic.

  Constraints are renamed before indexes because renaming a constraint that owns
  an index (the primary key) renames its index too; by the time the index loop
  runs, only standalone indexes are left.

  Deploy note: `release_command = "/app/bin/migrate"` (fly.toml,
  fly.production.toml) runs migrations before the new machines boot, so old code
  will query `behavioral_notes` after it is gone. Session-note paths — provider
  submit, parent approve/reject, staff roster, and child deletion — error for the
  deploy window. Bounded to that window; production deploys are triggered
  manually via `workflow_dispatch`, so schedule accordingly.
  """
  use Ecto.Migration

  def up do
    rename table(:behavioral_notes), to: table(:session_notes)
    rename_derived_objects("behavioral_notes_", "session_notes_", "session_notes")
  end

  def down do
    rename table(:session_notes), to: table(:behavioral_notes)
    rename_derived_objects("session_notes_", "behavioral_notes_", "behavioral_notes")
  end

  defp rename_derived_objects(from_prefix, to_prefix, table) do
    execute("""
    DO $$
    DECLARE
      obj record;
    BEGIN
      FOR obj IN
        SELECT conname AS name
        FROM pg_constraint
        WHERE conrelid = '#{table}'::regclass
          AND starts_with(conname, '#{from_prefix}')
      LOOP
        EXECUTE format(
          'ALTER TABLE #{table} RENAME CONSTRAINT %I TO %I',
          obj.name,
          '#{to_prefix}' || right(obj.name, -length('#{from_prefix}'))
        );
      END LOOP;

      FOR obj IN
        SELECT indexname AS name
        FROM pg_indexes
        WHERE tablename = '#{table}'
          AND starts_with(indexname, '#{from_prefix}')
      LOOP
        EXECUTE format(
          'ALTER INDEX %I RENAME TO %I',
          obj.name,
          '#{to_prefix}' || right(obj.name, -length('#{from_prefix}'))
        );
      END LOOP;
    END $$;
    """)
  end
end
