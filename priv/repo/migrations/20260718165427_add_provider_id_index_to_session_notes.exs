defmodule KlassHero.Repo.Migrations.AddProviderIdIndexToSessionNotes do
  use Ecto.Migration

  @moduledoc """
  Provider-scoped note lookups (`SessionNoteQueries.by_provider/2`) filter
  `provider_id`, but the only index touching it is the composite unique
  `(participation_record_id, provider_id)`, which can't serve a provider-only
  predicate. Index the FK directly.
  """

  def change do
    create index(:session_notes, [:provider_id])
  end
end
