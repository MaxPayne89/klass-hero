defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.ProviderProgramRepository do
  @moduledoc """
  Read-only repository for the provider_programs projection.

  Reads only — the projection GenServer handles all writes.
  """

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.ProviderProgramMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProgramProjectionSchema
  alias KlassHero.Repo

  def get_by_id(program_id) when is_binary(program_id) do
    fetch(ProviderProgramProjectionSchema, program_id)
  end

  @doc """
  Fetches a projected program owned by `provider_id`; foreign ≡ missing.

  The `provider_id` predicate is composed into the query, so a foreign row is
  never loaded rather than loaded-then-rejected.
  """
  def get_by_id(program_id, provider_id) when is_binary(program_id) and is_binary(provider_id) do
    ProviderProgramProjectionSchema
    |> where([p], p.provider_id == ^provider_id)
    |> fetch(program_id)
  end

  defp fetch(queryable, program_id) do
    case Repo.get(queryable, program_id) do
      nil -> {:error, :not_found}
      row -> {:ok, ProviderProgramMapper.to_read_model(row)}
    end
  end

  def list_by_provider(provider_id) when is_binary(provider_id) do
    ProviderProgramProjectionSchema
    |> where([p], p.provider_id == ^provider_id)
    |> order_by([p], asc: p.name)
    |> Repo.all()
    |> Enum.map(&ProviderProgramMapper.to_read_model/1)
  end
end
