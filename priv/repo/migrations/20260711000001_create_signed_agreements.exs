defmodule KlassHero.Repo.Migrations.CreateSignedAgreements do
  use Ecto.Migration

  def change do
    create table(:signed_agreements, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :provider_id, references(:providers, type: :binary_id, on_delete: :delete_all),
        null: false

      # Append-only consent evidence: a re-agreement (e.g. after a version bump) is a fresh row,
      # never an update — so there is deliberately no unique constraint that would block re-signing.
      add :kind, :string, null: false
      add :signed_by_name, :string, null: false
      add :signed_at, :utc_datetime_usec, null: false
      add :version, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:signed_agreements, [:provider_id])
  end
end
