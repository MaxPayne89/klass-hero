defmodule KlassHero.ProgramCatalog.Application.Queries.ListProviderPrograms do
  @moduledoc """
  Use case for listing programs for a specific provider from the program_listings read model (CQRS read side).
  """

  alias KlassHero.ProgramCatalog.Domain.ReadModels.ProgramListing

  @read_repository Application.compile_env!(
                     :klass_hero,
                     [:program_catalog, :for_listing_program_summaries]
                   )

  @spec execute(String.t()) :: [ProgramListing.t()]
  def execute(provider_id) when is_binary(provider_id) do
    @read_repository.list_for_provider(provider_id)
  end
end
