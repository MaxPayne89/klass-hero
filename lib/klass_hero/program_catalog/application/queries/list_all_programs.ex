defmodule KlassHero.ProgramCatalog.Application.Queries.ListAllPrograms do
  @moduledoc """
  Use case for listing all programs from the program_listings read model (CQRS read side).
  """

  alias KlassHero.ProgramCatalog.Domain.ReadModels.ProgramListing

  @read_repository Application.compile_env!(
                     :klass_hero,
                     [:program_catalog, :for_listing_program_summaries]
                   )

  @spec execute() :: [ProgramListing.t()]
  def execute do
    @read_repository.list_all()
  end
end
