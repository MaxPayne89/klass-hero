defmodule KlassHero.Provider.Adapters.Driven.Persistence.Mappers.IncidentReportMapper do
  @moduledoc """
  Maps between IncidentReport domain model and Ecto schema.

  Provides bidirectional conversion:
  - to_schema/1: IncidentReport -> map of attrs (for changeset/insert)
  - to_domain/1: IncidentReportSchema -> IncidentReport (for reading)

  ## Field Name Translation

  The database uses `provider_id` to reference the `providers` table.
  The domain model uses `provider_profile_id` for semantic clarity.
  This mapper handles the translation between these names.
  """

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.IncidentReportSchema
  alias KlassHero.Provider.Domain.Models.IncidentReport
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers

  @doc """
  Converts a domain IncidentReport into a map of attributes suitable for
  IncidentReportSchema.changeset/2.

  Field translation: provider_profile_id (domain) -> provider_id (DB).
  """
  @spec to_schema(IncidentReport.t()) :: map()
  def to_schema(%IncidentReport{} = report) do
    %{
      id: report.id,
      provider_id: report.provider_profile_id,
      reporter_user_id: report.reporter_user_id,
      reporter_display_name: report.reporter_display_name,
      program_id: report.program_id,
      session_id: report.session_id,
      category: report.category,
      severity: report.severity,
      description: report.description,
      occurred_at: report.occurred_at,
      photo_url: report.photo_url,
      original_filename: report.original_filename
    }
  end

  @doc """
  Converts an IncidentReportSchema into a domain IncidentReport entity.

  Field translation: provider_id (DB) -> provider_profile_id (domain).
  """
  @spec to_domain(IncidentReportSchema.t()) :: IncidentReport.t()
  def to_domain(%IncidentReportSchema{} = schema) do
    %IncidentReport{
      id: to_string(schema.id),
      provider_profile_id: to_string(schema.provider_id),
      reporter_user_id: to_string(schema.reporter_user_id),
      reporter_display_name: schema.reporter_display_name,
      program_id: MapperHelpers.maybe_to_string(schema.program_id),
      session_id: MapperHelpers.maybe_to_string(schema.session_id),
      category: schema.category,
      severity: schema.severity,
      description: schema.description,
      occurred_at: schema.occurred_at,
      photo_url: schema.photo_url,
      original_filename: schema.original_filename,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end
end
