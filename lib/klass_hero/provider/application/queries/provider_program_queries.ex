defmodule KlassHero.Provider.Application.Queries.ProviderProgramQueries do
  @moduledoc """
  Read-side queries over the `provider_programs` projection.

  The projection is fed by Program Catalog integration events; consumers in the
  web layer reach this module via `KlassHero.Provider`'s public API.
  """

  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.ProviderProgramRepository
  alias KlassHero.Provider.Domain.ReadModels.ProviderProgram

  @doc """
  Returns the provider-owned program by ID, or `{:error, :not_found}`.
  """
  @spec get_by_id(Ecto.UUID.t()) :: {:ok, ProviderProgram.t()} | {:error, :not_found}
  def get_by_id(program_id) when is_binary(program_id) do
    ProviderProgramRepository.get_by_id(program_id)
  end

  @doc """
  Lists all programs owned by the given provider, ordered by name asc.
  """
  @spec list_by_provider(Ecto.UUID.t()) :: [ProviderProgram.t()]
  def list_by_provider(provider_id) when is_binary(provider_id) do
    ProviderProgramRepository.list_by_provider(provider_id)
  end
end
