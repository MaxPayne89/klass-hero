defmodule KlassHero.Provider.Adapters.Driven.Persistence.Mappers.VettingCaseMapper do
  @moduledoc """
  Bidirectional mapping between `VettingCase` domain aggregates and `VettingCaseSchema` Ecto
  structs. The case's `steps` map through `VerificationStepMapper`.
  """

  import KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers, only: [maybe_add_id: 2]

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.VerificationStepMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VettingCaseSchema
  alias KlassHero.Provider.Domain.Models.VettingCase

  @doc """
  Converts a VettingCaseSchema (with `steps` preloaded) to a domain VettingCase.
  """
  def to_domain(%VettingCaseSchema{} = schema) do
    %VettingCase{
      id: to_string(schema.id),
      provider_id: to_string(schema.provider_id),
      entity_type: String.to_existing_atom(schema.entity_type),
      lifecycle: String.to_existing_atom(schema.lifecycle),
      steps: map_steps(schema.steps)
    }
  end

  @doc "Converts a domain VettingCase to a VettingCaseSchema attributes map (the case header only)."
  def to_schema(%VettingCase{} = case_) do
    %{
      provider_id: case_.provider_id,
      entity_type: Atom.to_string(case_.entity_type),
      lifecycle: Atom.to_string(case_.lifecycle)
    }
    |> maybe_add_id(case_.id)
  end

  defp map_steps(steps) when is_list(steps), do: Enum.map(steps, &VerificationStepMapper.to_domain/1)
  defp map_steps(_not_loaded), do: []
end
