defmodule KlassHeroWeb.Presenters.IncidentReportPresenter do
  @moduledoc """
  Pure functions that transform `IncidentReportSummary` read-models into
  display-ready maps for the per-program incidents listing.
  """

  alias KlassHero.Provider.Domain.ReadModels.IncidentReportSummary
  alias KlassHero.Provider.IncidentReport

  @type list_view :: %{
          id: String.t(),
          category_label: String.t(),
          severity_label: String.t(),
          severity_color: String.t(),
          occurred_at_display: String.t(),
          reporter_display_name: String.t(),
          description: String.t()
        }

  @spec to_list_view(IncidentReportSummary.t()) :: list_view()
  def to_list_view(%IncidentReportSummary{} = summary) do
    %{
      id: summary.id,
      category_label: IncidentReport.category_label(summary.category),
      severity_label: IncidentReport.severity_label(summary.severity),
      severity_color: severity_color(summary.severity),
      occurred_at_display: format_occurred_at(summary.occurred_at),
      reporter_display_name: summary.reporter_display_name,
      description: summary.description
    }
  end

  @spec severity_color(IncidentReport.severity()) :: String.t()
  def severity_color(:critical), do: "error"
  def severity_color(:high), do: "warning"
  def severity_color(:medium), do: "info"
  def severity_color(:low), do: "success"

  defp format_occurred_at(nil), do: ""

  defp format_occurred_at(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
