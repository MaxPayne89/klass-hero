defmodule KlassHero.ProgramCatalog.Application.Queries.ProgramCatalogQueries do
  @moduledoc """
  Query module for program catalog repository reads.

  Centralises read operations that depend on the program repository,
  including provider program counts, ended program lookups, batch fetches,
  and form changeset construction.
  """

  @repository Application.compile_env!(:klass_hero, [:program_catalog, :repository])

  @doc """
  Returns IDs of programs whose end_date is before the given cutoff date.

  Used by the Messaging context's retention policy to archive broadcast
  conversations for ended programs.
  """
  @spec list_ended_program_ids(Date.t()) :: [String.t()]
  def list_ended_program_ids(cutoff_date) do
    @repository.list_ended_program_ids(cutoff_date)
  end

  @doc """
  Fetches multiple programs by a list of IDs in a single database query.

  Returns a list of Program structs for all matching IDs. IDs with no corresponding
  program are silently omitted.
  """
  @spec get_programs_by_ids([String.t()]) :: [struct()]
  def get_programs_by_ids(ids) when is_list(ids) do
    @repository.get_by_ids(ids)
  end

  @doc """
  Returns an empty changeset for the program creation form.
  """
  def new_program_changeset(attrs \\ %{}) do
    @repository.new_changeset(attrs)
  end
end
