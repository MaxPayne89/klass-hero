defmodule KlassHero.Provider.Adapters.Driven.Persistence.Mappers.ProviderProgramMapper do
  @moduledoc false

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProgramProjectionSchema
  alias KlassHero.Provider.Domain.ReadModels.ProviderProgram

  @spec to_read_model(ProviderProgramProjectionSchema.t()) :: ProviderProgram.t()
  def to_read_model(%ProviderProgramProjectionSchema{} = row) do
    %ProviderProgram{
      program_id: row.program_id,
      provider_id: row.provider_id,
      name: row.name,
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    }
  end
end
