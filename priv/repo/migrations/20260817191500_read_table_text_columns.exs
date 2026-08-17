defmodule KlassHero.Repo.Migrations.ReadTableTextColumns do
  @moduledoc """
  Drops every length cap from the projection read tables, and the two dead
  `icon_path` columns with them.

  A read table has no changeset — the projection is its only writer — so a
  `varchar(n)` there can never reject an over-long value. It can only raise
  Postgres 22001 inside `EventDeliveryWorker`, burn all ten Oban attempts and
  discard the event, losing every field of that update: #1376, where a 295- and a
  318-character `cover_image_url` froze two public listings three edits behind
  their programs.

  `varchar(n) -> text` is binary-coercible in Postgres, so no table is rewritten;
  indexes on the converted columns rebuild under a brief lock.

  `icon_path` is dead on both sides — no schema field on `Program` or
  `ProgramListing`, and the projection discards it from stale payloads — so
  dropping it cannot break the release still serving during the migration.

  `down` restores the caps but is irreversible for data: a value longer than the
  restored limit fails the reverse.
  """

  use Ecto.Migration

  def up do
    alter table(:program_listings) do
      modify :title, :text
      modify :category, :text
      modify :age_range, :text
      modify :pricing_period, :text
      modify :location, :text
      modify :cover_image_url, :text
      modify :season, :text
      modify :meeting_days, {:array, :text}
      remove :icon_path
    end

    alter table(:conversation_summaries) do
      modify :subject, :text
      modify :other_participant_name, :text
      modify :program_name, :text
      modify :conversation_type, :text
      modify :enrolled_child_names, {:array, :text}
    end

    alter table(:messaging_enrolled_children) do
      modify :child_first_name, :text
    end

    alter table(:provider_programs) do
      modify :name, :text
    end

    alter table(:provider_session_details) do
      modify :program_title, :text
      modify :status, :text
      modify :current_assigned_staff_name, :text
      modify :cover_staff_name, :text
    end

    alter table(:provider_session_stats) do
      modify :program_title, :text
    end

    alter table(:programs) do
      remove :icon_path
    end
  end

  def down do
    alter table(:program_listings) do
      modify :title, :string
      modify :category, :string
      modify :age_range, :string
      modify :pricing_period, :string
      modify :location, :string
      modify :cover_image_url, :string
      modify :season, :string
      modify :meeting_days, {:array, :string}
      add :icon_path, :string
    end

    alter table(:conversation_summaries) do
      modify :subject, :string
      modify :other_participant_name, :string
      modify :program_name, :string
      modify :conversation_type, :string
      modify :enrolled_child_names, {:array, :string}
    end

    alter table(:messaging_enrolled_children) do
      modify :child_first_name, :string
    end

    alter table(:provider_programs) do
      modify :name, :string
    end

    alter table(:provider_session_details) do
      modify :program_title, :string
      modify :status, :string
      modify :current_assigned_staff_name, :string
      modify :cover_staff_name, :string
    end

    alter table(:provider_session_stats) do
      modify :program_title, :string
    end

    alter table(:programs) do
      add :icon_path, :text
    end
  end
end
