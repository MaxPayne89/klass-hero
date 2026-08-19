defmodule KlassHero.Repo.Migrations.CreateWaiverTables do
  @moduledoc """
  Provider-authored waivers parents sign at enrollment (#828), owned by Enrollment.

  Three tables rather than one, because a waiver's *text* must stay reproducible verbatim
  after later edits: `waivers` is the durable identity, `waiver_versions` is append-only
  text history, and `waiver_acceptances` is the legal record binding a signature to the
  exact version signed.

  Deletion rules are deliberately conservative. Every FK here is `:restrict`, and
  `program_id` carries no FK at all:

    * `program_id` is a cross-context reference into Program Catalog, so it is a bare
      correlation id per ADR-0001. The sibling `participant_policies`/`enrollment_policies`
      use `on_delete: :delete_all` instead — copying that would let a program deletion
      cascade away signed legal records, running no changeset and staging no event.
    * `:restrict` on the in-context FKs means a waiver or version that has been signed
      cannot be deleted out from under its acceptance. Waivers are retired with
      `archived_at`, never removed.
  """

  use Ecto.Migration

  def up do
    create table(:waivers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # Cross-context correlation id (ADR-0001) — no FK, so a program deletion can never
      # cascade into signed waiver records.
      add :program_id, :binary_id, null: false
      add :title, :string, null: false
      add :required, :boolean, null: false, default: true
      add :archived_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:waivers, [:program_id])
    create index(:waivers, [:program_id], where: "archived_at IS NULL", name: :waivers_active_idx)

    create table(:waiver_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :waiver_id,
          references(:waivers, type: :binary_id, on_delete: :restrict),
          null: false

      add :body, :text, null: false
      add :version, :integer, null: false
      add :published_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:waiver_versions, [:waiver_id])
    create unique_index(:waiver_versions, [:waiver_id, :version])

    create constraint(:waiver_versions, :waiver_version_positive, check: "version >= 1")

    create table(:waiver_acceptances, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :waiver_version_id,
          references(:waiver_versions, type: :binary_id, on_delete: :restrict),
          null: false

      add :waiver_id,
          references(:waivers, type: :binary_id, on_delete: :restrict),
          null: false

      add :enrollment_id,
          references(:enrollments, type: :binary_id, on_delete: :restrict),
          null: false

      # Family's parent profile — cross-context correlation id, no FK (ADR-0001).
      add :parent_id, :binary_id, null: false
      add :accepted_at, :utc_datetime_usec, null: false
      # Nullable on purpose: absent or untrusted forwarded headers store nothing rather
      # than a proxy IP, which would look like evidence without being any.
      add :ip_address, :string
      add :user_agent, :text
      # Redundant copy of the version's body at signing time. The version row is the
      # source of truth; this survives even a catastrophic loss of that table.
      add :body_snapshot, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:waiver_acceptances, [:enrollment_id])
    create index(:waiver_acceptances, [:waiver_version_id])
    create index(:waiver_acceptances, [:parent_id])
    create unique_index(:waiver_acceptances, [:enrollment_id, :waiver_id])
  end

  def down do
    drop table(:waiver_acceptances)
    drop table(:waiver_versions)
    drop table(:waivers)
  end
end
