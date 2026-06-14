defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.ProviderProgramRepository do
  @moduledoc """
  Read-only repository for the provider_programs projection.

  Implements the ForQueryingProviderPrograms port. This repository only reads —
  the projection GenServer handles all writes.
  """

  @behaviour KlassHero.Provider.Domain.Ports.ForQueryingProviderPrograms

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.ProviderProgramMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProgramProjectionSchema
  alias KlassHero.Repo

  @impl true
  def get_by_id(program_id) when is_binary(program_id) do
    db_interaction operation: :get_by_id, entity: "provider_program" do
      case Repo.get(ProviderProgramProjectionSchema, program_id) do
        nil -> {:error, :not_found}
        row -> {:ok, ProviderProgramMapper.to_read_model(row)}
      end
    end
  end

  @impl true
  def list_by_provider(provider_id) when is_binary(provider_id) do
    db_interaction operation: :list_by_provider, entity: "provider_program" do
      ProviderProgramProjectionSchema
      |> where([p], p.provider_id == ^provider_id)
      |> order_by([p], asc: p.name)
      |> Repo.all()
      |> Enum.map(&ProviderProgramMapper.to_read_model/1)
    end
  end
end
