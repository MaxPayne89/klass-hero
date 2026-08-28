defmodule KlassHero.Provider.Programs do
  @moduledoc """
  Read-side queries over a provider's programs and sessions.

  Backed by the `provider_programs` and `provider_session_details` projections
  (fed by Program Catalog / Participation integration events), plus a live
  cross-context count for completed sessions. Consumers reach these through
  `KlassHero.Provider`'s public API — this module is internal to the Provider
  context.

  Queries sit here rather than behind repository modules, matching
  `KlassHero.Provider.Incidents` and the Program Catalog / Messaging read sides.
  """

  import Ecto.Query

  alias KlassHero.Provider.ParticipationSessionStatsACL
  alias KlassHero.Provider.SessionDetail
  alias KlassHero.Repo

  @doc "Returns the total session count across all of a provider's programs."
  @spec get_total_session_count(String.t()) :: non_neg_integer()
  def get_total_session_count(provider_id) when is_binary(provider_id) do
    ParticipationSessionStatsACL.total_completed_sessions(provider_id)
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
