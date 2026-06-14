defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.SessionDetailsRepository do
  @moduledoc "Read-only repository for the provider_session_details projection."

  @behaviour KlassHero.Provider.Domain.Ports.ForQueryingSessionDetails

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.ProviderSessionDetailMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderSessionDetailSchema
  alias KlassHero.Repo

  @impl true
  def list_by_program(provider_id, program_id) when is_binary(provider_id) and is_binary(program_id) do
    db_interaction operation: :list_by_program, entity: "session_detail" do
      from(d in ProviderSessionDetailSchema,
        where: d.provider_id == ^provider_id and d.program_id == ^program_id,
        order_by: [asc: d.session_date, asc: d.start_time]
      )
      |> Repo.all()
      |> Enum.map(&ProviderSessionDetailMapper.to_read_model/1)
    end
  end

  @impl true
  def get_by_id(session_id) when is_binary(session_id) do
    db_interaction operation: :get_by_id, entity: "session_detail" do
      case Repo.get(ProviderSessionDetailSchema, session_id) do
        nil -> {:error, :not_found}
        row -> {:ok, ProviderSessionDetailMapper.to_read_model(row)}
      end
    end
  end
end
