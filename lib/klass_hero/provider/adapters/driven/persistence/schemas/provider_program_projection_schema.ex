defmodule KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProgramProjectionSchema do
  @moduledoc """
  Read table for the Provider's per-program projection (issue #34).

  Populated by the `ProviderPrograms` projection from Program Catalog
  integration events. Do not write directly — use the projection.
  """

  use Ecto.Schema

  @primary_key {:program_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "provider_programs" do
    field :provider_id, :binary_id
    field :name, :string

    timestamps(type: :utc_datetime)
  end
end
