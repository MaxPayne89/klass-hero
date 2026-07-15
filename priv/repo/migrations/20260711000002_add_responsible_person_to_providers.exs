defmodule KlassHero.Repo.Migrations.AddResponsiblePersonToProviders do
  use Ecto.Migration

  # A :business provider designates a Responsible Person — the owner/director legally
  # accountable for the business (ADR-0010). Modelled as two values on the provider row,
  # not a first-class entity: there is no history table. Nullable — unset until the
  # business fills the B1 identity step; individual providers never populate these.
  def change do
    alter table(:providers) do
      add :responsible_person_name, :string
      add :responsible_person_role, :string
    end
  end
end
