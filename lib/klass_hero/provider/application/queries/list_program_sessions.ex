defmodule KlassHero.Provider.Application.Queries.ListProgramSessions do
  @moduledoc "Lists per-session detail rows for a provider's program."

  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.SessionDetailsRepository
  alias KlassHero.Provider.Domain.ReadModels.SessionDetail

  @spec execute(binary(), binary()) :: [SessionDetail.t()]
  def execute(provider_id, program_id), do: SessionDetailsRepository.list_by_program(provider_id, program_id)
end
