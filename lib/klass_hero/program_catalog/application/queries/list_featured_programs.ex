defmodule KlassHero.ProgramCatalog.Application.Queries.ListFeaturedPrograms do
  @moduledoc """
  Returns the first 2 non-expired programs (ordered by title) for the home page featured section.
  Programs with a nil `end_date` are treated as open-ended (see issue #610).
  """

  alias KlassHero.ProgramCatalog.Domain.ReadModels.ProgramListing

  @read_repository Application.compile_env!(
                     :klass_hero,
                     [:program_catalog, :for_listing_program_summaries]
                   )

  @featured_count 2

  @spec execute() :: [ProgramListing.t()]
  def execute do
    @read_repository.list_active()
    |> Enum.take(@featured_count)
  end
end
