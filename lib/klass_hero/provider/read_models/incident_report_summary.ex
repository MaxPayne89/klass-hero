defmodule KlassHero.Provider.ReadModels.IncidentReportSummary do
  @moduledoc """
  Read-model projection of an incident report for the per-program listing.

  Display-optimized; contains no business logic. Reporter identity is
  captured at submit time as a snapshot — not resolved live — so this
  struct intentionally has no `reporter_user_id` field.
  """

  alias KlassHero.Provider.IncidentReport

  @typedoc "A denormalized incident report row for the per-program incidents view."
  @type t :: %__MODULE__{
          id: String.t(),
          provider_id: String.t(),
          program_id: String.t() | nil,
          session_id: String.t() | nil,
          category: IncidentReport.category(),
          severity: IncidentReport.severity(),
          description: String.t(),
          occurred_at: DateTime.t(),
          reporter_display_name: String.t()
        }

  @enforce_keys [
    :id,
    :provider_id,
    :category,
    :severity,
    :description,
    :occurred_at,
    :reporter_display_name
  ]

  defstruct [
    :id,
    :provider_id,
    :program_id,
    :session_id,
    :category,
    :severity,
    :description,
    :occurred_at,
    :reporter_display_name
  ]

  @doc """
  Builds a summary from an `IncidentReport`.

  Narrowing, not copying: `reporter_user_id` is dropped (see the moduledoc) and
  UUIDs are stringified for display.
  """
  @spec from_report(IncidentReport.t()) :: t()
  def from_report(%IncidentReport{} = report) do
    %__MODULE__{
      id: to_string(report.id),
      provider_id: to_string(report.provider_profile_id),
      program_id: report.program_id && to_string(report.program_id),
      session_id: report.session_id && to_string(report.session_id),
      category: report.category,
      severity: report.severity,
      description: report.description,
      occurred_at: report.occurred_at,
      reporter_display_name: report.reporter_display_name
    }
  end
end
