defmodule KlassHero.Repo.Migrations.DropRetiredProjectionReadTables do
  use Ecto.Migration

  # Four CQRS read tables whose projections were deleted in this release. Each was
  # derivable from write tables the application still owns:
  #
  #   program_listings            1:1 mirror of `programs`, same context
  #   provider_programs           three columns of `programs`, mirrored into Provider
  #   provider_session_stats      a counter over `program_sessions`
  #   messaging_enrolled_children a join of `enrollments`/`children`/`parents`
  #
  # up/down rather than change: Ecto cannot reverse a table drop. `down` recreates
  # the empty tables with their indexes so a rollback leaves a valid schema. It
  # cannot restore rows, which is acceptable — every one of these was a copy, and
  # nothing writes them any more.
  #
  # Fly runs migrations as a release_command, before new machines take traffic, so
  # this executes while the previous release is still serving and still reading
  # these tables. That window is a deliberate, accepted cost here; #1321 split its
  # equivalent drop across two releases to avoid it.
  def up do
    drop table(:program_listings)
    drop table(:provider_programs)
    drop table(:provider_session_stats)
    drop table(:messaging_enrolled_children)
  end

  def down do
    create table(:program_listings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :text, null: false
      add :subtitle, :text
      add :description, :text
      add :category, :text
      add :age_range, :text
      add :price, :decimal
      add :pricing_period, :text
      add :location, :text
      add :cover_image_url, :text
      add :start_date, :date
      add :end_date, :date
      add :meeting_days, {:array, :text}, default: []
      add :meeting_start_time, :time
      add :meeting_end_time, :time
      add :season, :text
      add :registration_start_date, :date
      add :registration_end_date, :date
      add :provider_id, :binary_id, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:program_listings, [:inserted_at, :id], name: :program_listings_cursor_idx)
    create index(:program_listings, [:category])
    create index(:program_listings, [:provider_id])
    create index(:program_listings, [:end_date])

    create table(:provider_programs, primary_key: false) do
      add :program_id, :binary_id, primary_key: true
      add :provider_id, :binary_id, null: false
      add :name, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:provider_programs, [:provider_id])

    create table(:provider_session_stats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider_id, :binary_id, null: false
      add :program_id, :binary_id, null: false
      add :program_title, :text, null: false
      add :sessions_completed_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:provider_session_stats, [:provider_id])
    create unique_index(:provider_session_stats, [:provider_id, :program_id])

    create table(:messaging_enrolled_children, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :parent_user_id, :binary_id, null: false
      add :program_id, :binary_id, null: false
      add :child_id, :binary_id, null: false
      add :child_first_name, :text

      timestamps(type: :utc_datetime)
    end

    create index(:messaging_enrolled_children, [:child_id])
    create index(:messaging_enrolled_children, [:parent_user_id, :program_id])
    create unique_index(:messaging_enrolled_children, [:parent_user_id, :program_id, :child_id])
  end
end
