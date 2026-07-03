defmodule KlassHero.Provider.Adapters.Driven.Persistence.Mappers.IncidentReportSummaryMapper do
  @moduledoc """
  Maps an `IncidentReportSchema` row into the `IncidentReportSummary`
  read-model used by the per-program incidents listing.
  """

  alias KlassHero.Provider.Domain.ReadModels.IncidentReportSummary
  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers

  @spec from_schema(IncidentReport.t()) :: IncidentReportSummary.t()
  def from_schema(%IncidentReport{} = report) do
    %IncidentReportSummary{
      id: to_string(report.id),
      provider_id: to_string(report.provider_profile_id),
      program_id: MapperHelpers.maybe_to_string(report.program_id),
      session_id: MapperHelpers.maybe_to_string(report.session_id),
      category: report.category,
      severity: report.severity,
      description: report.description,
      occurred_at: report.occurred_at,
      reporter_display_name: report.reporter_display_name
    }
  end
end
