defmodule KlassHeroWeb.Admin.Filters.IncidentSeverityFilter do
  @moduledoc false

  use Backpex.Filters.Boolean

  import Ecto.Query

  alias Backpex.Filters.Boolean
  alias KlassHero.Provider.IncidentReport

  @impl Backpex.Filter
  def label, do: "Severity"

  # Options are derived from the entity so the list cannot drift from the enum.
  @impl Boolean
  def options(_assigns) do
    for severity <- IncidentReport.valid_severities() do
      %{
        label: IncidentReport.severity_label(severity),
        key: Atom.to_string(severity),
        predicate: dynamic([x], x.severity == ^severity)
      }
    end
  end
end
