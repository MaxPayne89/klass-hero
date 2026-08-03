defmodule KlassHero.Provider.Incidents do
  @moduledoc """
  Incident report commands and queries for the Provider context.

  Submission delegates to the `SubmitIncidentReport` use case; reads assemble
  program-direct and session-linked reports into display summaries. Reached
  through `KlassHero.Provider`'s public API.
  """

  import Ecto.Query, warn: false

  alias KlassHero.Provider.Domain.ReadModels.IncidentReportSummary
  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Provider.SessionDetail
  alias KlassHero.Provider.SubmitIncidentReport
  alias KlassHero.Repo

  @doc "Submits an incident report from a provider (see `SubmitIncidentReport`)."
  def submit_incident_report(params) when is_map(params) do
    SubmitIncidentReport.execute(params)
  end

  @doc """
  Lists incident report summaries for a program owned by the given provider.

  Includes both program-direct and session-linked reports. Ordered by
  `occurred_at` descending. Returns `[]` for unknown or unowned programs.
  """
  @spec list_incident_reports_for_program(String.t(), String.t()) ::
          [IncidentReportSummary.t()]
  def list_incident_reports_for_program(provider_id, program_id)
      when is_binary(provider_id) and is_binary(program_id) do
    program_direct = list_incidents_program_direct(provider_id, program_id)
    session_linked = list_incidents_session_linked(provider_id, program_id)

    (program_direct ++ session_linked)
    |> Enum.sort_by(& &1.occurred_at, {:desc, DateTime})
    |> Enum.map(&IncidentReportSummary.from_report/1)
  end

  @doc "Retrieves a single incident report by ID (used by the notification worker)."
  @spec get_incident_report(String.t()) :: {:ok, IncidentReport.t()} | {:error, :not_found}
  def get_incident_report(id) when is_binary(id) do
    case Repo.get(IncidentReport, id) do
      nil -> {:error, :not_found}
      report -> {:ok, report}
    end
  end

  defp list_incidents_program_direct(provider_id, program_id) do
    IncidentReport
    |> where([r], r.provider_profile_id == ^provider_id and r.program_id == ^program_id)
    |> Repo.all()
  end

  # Session-linked reports match through the provider_session_details projection.
  defp list_incidents_session_linked(provider_id, program_id) do
    from(r in IncidentReport,
      join: s in SessionDetail,
      on: s.session_id == r.session_id,
      where:
        r.provider_profile_id == ^provider_id and
          s.provider_id == ^provider_id and
          s.program_id == ^program_id,
      select: r
    )
    |> Repo.all()
  end
end
