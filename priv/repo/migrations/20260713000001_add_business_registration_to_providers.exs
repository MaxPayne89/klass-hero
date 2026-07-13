defmodule KlassHero.Repo.Migrations.AddBusinessRegistrationToProviders do
  use Ecto.Migration

  # A :business provider proves legal registration (vetting step B2, issue #956) by
  # supplying structured facts about the entity — legal name, registration number, and
  # country of registration — alongside the uploaded document. Modelled as three values
  # on the provider row (not on the document, not a first-class entity), so the admin
  # review queue can surface them without opening the file and future automated registry
  # lookups have structured data to work with (ADR-0011). Nullable — unset until the
  # business submits B2; individual providers never populate these. registration_country
  # is a curated string ("DE" | "GB" | "OTHER"), not an enum, so the whitelist widens
  # without a migration.
  def change do
    alter table(:providers) do
      add :legal_business_name, :string
      add :registration_number, :string
      add :registration_country, :string
    end
  end
end
