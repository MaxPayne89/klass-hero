defmodule KlassHero.Repo.Migrations.AddEntityTypeToSignedAgreements do
  @moduledoc """
  Snapshots the provider's `entity_type` onto each `signed_agreements` row at sign time, so an
  agreement is self-describing for reporting (individual Step-6 vs business B4) without a join back
  to `providers`, whose live `entity_type` could in principle drift from the track the agreement was
  actually signed under.

  Nullable with no backfill: the table is append-only consent evidence, so historical rows keep a
  null `entity_type` (they predate the column) and only new signings carry it. The submit command
  stamps it; the schema treats it as optional so legacy rows stay valid.
  """

  use Ecto.Migration

  def change do
    alter table(:signed_agreements) do
      add :entity_type, :string
    end
  end
end
