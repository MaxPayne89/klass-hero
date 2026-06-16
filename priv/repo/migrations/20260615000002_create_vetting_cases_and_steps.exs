defmodule KlassHero.Repo.Migrations.CreateVettingCasesAndSteps do
  use Ecto.Migration

  def change do
    create table(:vetting_cases, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :provider_id, references(:providers, type: :binary_id, on_delete: :delete_all),
        null: false

      add :entity_type, :string, null: false
      add :lifecycle, :string, null: false, default: "not_started"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:vetting_cases, [:provider_id])

    create table(:verification_steps, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :vetting_case_id, references(:vetting_cases, type: :binary_id, on_delete: :delete_all),
        null: false

      add :key, :string, null: false
      add :status, :string, null: false, default: "not_started"
      add :completed_via, :string, null: false
      add :requires, {:array, :string}, null: false, default: []
      add :admin_review, :boolean, null: false, default: false
      # Polymorphic reference to the evidence record (VerificationDocument today; other
      # evidence kinds later) — intentionally not a FK so the evidence kind can vary.
      add :evidence_ref, :binary_id
      add :rejection_reason, :string
      add :reviewed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime_usec
      add :submitted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:verification_steps, [:vetting_case_id])
    create unique_index(:verification_steps, [:vetting_case_id, :key])
  end
end
