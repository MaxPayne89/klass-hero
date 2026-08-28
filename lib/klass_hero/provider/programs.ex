defmodule KlassHero.Provider.Programs do
  @moduledoc """
  Read-side queries over a provider's programs and sessions.

  Backed by the `provider_session_details` projection (fed by Participation
  integration events), plus facade reads into ProgramCatalog and Participation.
  Consumers reach these through `KlassHero.Provider`'s public API — this module
  is internal to the Provider context.

  Queries sit here rather than behind repository modules, matching
  `KlassHero.Provider.Incidents` and the Program Catalog / Messaging read sides.
  """

  import Ecto.Query

  alias KlassHero.Participation
  alias KlassHero.ProgramCatalog
  alias KlassHero.Provider.SessionDetail
  alias KlassHero.Repo

  @doc """
  Returns the total session count across all of a provider's programs.

  Two facade calls rather than one cross-schema join: ProgramCatalog owns which
  programs are a provider's, Participation owns which sessions completed, and
  neither relationship is Provider's to join. `resolve_provider_scope/1` in
  Participation resolves a provider the same way.
  """
  @spec get_total_session_count(String.t()) :: non_neg_integer()
  def get_total_session_count(provider_id) when is_binary(provider_id) do
    provider_id
    |> ProgramCatalog.list_program_ids_for_provider()
    |> Participation.count_completed_sessions()
  end

  @doc """
  Lists per-session detail rows for a provider's program from the
  `provider_session_details` projection. Cross-provider lookups return `[]`.
  """
  @spec list_program_sessions(String.t(), String.t()) :: [SessionDetail.t()]
  def list_program_sessions(provider_id, program_id) when is_binary(provider_id) and is_binary(program_id) do
    from(d in SessionDetail,
      where: d.provider_id == ^provider_id and d.program_id == ^program_id,
      order_by: [asc: d.session_date, asc: d.start_time]
    )
    |> Repo.all()
  end

  @doc """
  Returns one projected session row by ID, **unscoped**.

  Used by `SubmitIncidentReport` to resolve the program a reported session
  belongs to, where no provider is yet in scope.
  """
  @spec get_session_detail(String.t()) :: {:ok, SessionDetail.t()} | {:error, :not_found}
  def get_session_detail(session_id) when is_binary(session_id) do
    fetch(SessionDetail, session_id)
  end

  defp fetch(queryable, id) do
    case Repo.get(queryable, id) do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end
end
