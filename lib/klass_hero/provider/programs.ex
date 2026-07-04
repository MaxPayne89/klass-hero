defmodule KlassHero.Provider.Programs do
  @moduledoc """
  Read-side queries over a provider's programs and sessions.

  Backed by the `provider_programs` and `provider_session_details` projections
  (fed by Program Catalog / Participation integration events) and the session
  stats read table. Consumers reach these through `KlassHero.Provider`'s public
  API — this module is internal to the Provider context.
  """

  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.ProviderProgramRepository
  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.SessionDetailsRepository
  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.SessionStatsRepository
  alias KlassHero.Provider.Domain.ReadModels.ProviderProgram
  alias KlassHero.Provider.Domain.ReadModels.SessionDetail

  @doc "Returns the total session count across all of a provider's programs."
  @spec get_total_session_count(String.t()) :: non_neg_integer()
  def get_total_session_count(provider_id) when is_binary(provider_id) do
    SessionStatsRepository.get_total_count(provider_id)
  end

  @doc """
  Lists per-session detail rows for a provider's program from the
  `provider_session_details` projection. Cross-provider lookups return `[]`.
  """
  @spec list_program_sessions(String.t(), String.t()) :: [SessionDetail.t()]
  def list_program_sessions(provider_id, program_id) when is_binary(provider_id) and is_binary(program_id) do
    SessionDetailsRepository.list_by_program(provider_id, program_id)
  end

  @doc "Returns the provider-owned program by ID from the `provider_programs` projection."
  @spec get_provider_program(String.t()) :: {:ok, ProviderProgram.t()} | {:error, :not_found}
  def get_provider_program(program_id) when is_binary(program_id) do
    ProviderProgramRepository.get_by_id(program_id)
  end

  @doc "Lists all programs owned by the given provider, ordered by name asc."
  @spec list_provider_programs(String.t()) :: [ProviderProgram.t()]
  def list_provider_programs(provider_id) when is_binary(provider_id) do
    ProviderProgramRepository.list_by_provider(provider_id)
  end
end
