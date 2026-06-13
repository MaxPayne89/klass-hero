defmodule KlassHero.ProgramCatalog.Application.Queries.GetProgramById do
  @moduledoc """
  Use case for retrieving a single program by ID from the Program Catalog.
  """

  alias KlassHero.ProgramCatalog.Domain.Models.Program
  alias KlassHero.ProgramCatalog.Domain.Ports.ForListingPrograms

  @doc """
  Returns `{:ok, Program.t()}` for the given ID, or `{:error, :not_found}` if missing/invalid.
  """
  @spec execute(String.t()) ::
          {:ok, Program.t()} | {:error, :not_found | ForListingPrograms.list_error()}
  def execute(id) when is_binary(id) do
    repository_module().get_by_id(id)
  end

  defp repository_module do
    Application.get_env(:klass_hero, :program_catalog)[:repository]
  end
end
