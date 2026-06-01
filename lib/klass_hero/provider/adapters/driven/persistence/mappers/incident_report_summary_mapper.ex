defmodule KlassHero.Provider.Adapters.Driven.Persistence.Mappers.IncidentReportSummaryMapper do
  @moduledoc """
  Maps an `IncidentReportSchema` row into the `IncidentReportSummary`
  read-model used by the per-program incidents listing.
  """

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.IncidentReportSchema
  alias KlassHero.Provider.Domain.ReadModels.IncidentReportSummary
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers

  @spec from_schema(IncidentReportSchema.t()) :: IncidentReportSummary.t()
  def from_schema(%IncidentReportSchema{} = schema) do
    %IncidentReportSummary{
      id: to_string(schema.id),
      provider_id: to_string(schema.provider_id),
      program_id: MapperHelpers.maybe_to_string(schema.program_id),
      session_id: MapperHelpers.maybe_to_string(schema.session_id),
      category: schema.category,
      severity: schema.severity,
      description: schema.description,
      occurred_at: schema.occurred_at,
      reporter_display_name: schema.reporter_display_name
    }
  end
end
