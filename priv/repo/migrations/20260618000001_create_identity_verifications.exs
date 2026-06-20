defmodule KlassHero.Repo.Migrations.CreateIdentityVerifications do
  use Ecto.Migration

  def change do
    create table(:identity_verifications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :provider_id, references(:providers, type: :binary_id, on_delete: :delete_all),
        null: false

      # The Stripe Identity session id — the only Stripe reference we keep. Unique so the webhook
      # handler can dedup on it (ADR-0007). No DOB and no document images are ever stored.
      add :stripe_session_id, :string, null: false
      add :status, :string, null: false, default: "processing"
      add :outcome, :string
      add :failure_reason, :string
      add :verified_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:identity_verifications, [:stripe_session_id])
    create index(:identity_verifications, [:provider_id])
  end
end
