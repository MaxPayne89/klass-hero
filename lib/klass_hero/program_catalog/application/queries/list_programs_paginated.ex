defmodule KlassHero.ProgramCatalog.Application.Queries.ListProgramsPaginated do
  @moduledoc """
  Use case for listing programs with cursor-based pagination.

  Reads from the denormalized program_listings read model (CQRS read side).
  Supports optional category filtering at the database level.

  ## Example

      # Get first page with 20 programs
      {:ok, page_result} = ListProgramsPaginated.execute(20, nil)

      # Get next page using cursor from previous result
      {:ok, next_page} = ListProgramsPaginated.execute(20, page_result.next_cursor)

      # Get programs filtered by category
      {:ok, sports_programs} = ListProgramsPaginated.execute(20, nil, "sports")

  Infrastructure errors (connection, query) are not caught - they crash and
  are handled by the supervision tree.
  """

  alias KlassHero.ProgramCatalog.Domain.Services.ProgramCategories

  @read_repository Application.compile_env!(
                     :klass_hero,
                     [:program_catalog, :for_listing_program_summaries]
                   )

  def execute(limit, cursor) do
    execute(limit, cursor, nil)
  end

  def execute(limit, cursor, category) do
    validated_category = ProgramCategories.validate_filter(category)
    @read_repository.list_paginated(limit, cursor, validated_category)
  end
end
