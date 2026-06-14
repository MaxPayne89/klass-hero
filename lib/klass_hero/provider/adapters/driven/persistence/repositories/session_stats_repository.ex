defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.SessionStatsRepository do
  @moduledoc """
  Read-side repository for the provider_session_stats denormalized table.

  Implements the ForQueryingSessionStats port. This repository only reads —
  the projection GenServer handles all writes.

  Returns lightweight SessionStats DTOs (no domain entities, no value objects).
  """

  @behaviour KlassHero.Provider.Domain.Ports.ForQueryingSessionStats

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.SessionStatsSchema
  alias KlassHero.Provider.Domain.ReadModels.SessionStats
  alias KlassHero.Repo

  @impl true
  def list_for_provider(provider_id) when is_binary(provider_id) do
    db_interaction operation: :list_for_provider, entity: "session_stats" do
      SessionStatsSchema
      |> where([s], s.provider_id == ^provider_id)
      |> order_by([s], desc: s.sessions_completed_count)
      |> Repo.all()
      |> Enum.map(&to_dto/1)
    end
  end

  @impl true
  def get_total_count(provider_id) when is_binary(provider_id) do
    db_interaction operation: :get_total_count, entity: "session_stats" do
      SessionStatsSchema
      |> where([s], s.provider_id == ^provider_id)
      |> select([s], coalesce(sum(s.sessions_completed_count), 0))
      |> Repo.one()
    end
  end

  defp to_dto(%SessionStatsSchema{} = schema) do
    SessionStats.new(%{
      id: schema.id,
      provider_id: schema.provider_id,
      program_id: schema.program_id,
      program_title: schema.program_title,
      sessions_completed_count: schema.sessions_completed_count,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    })
  end
end
