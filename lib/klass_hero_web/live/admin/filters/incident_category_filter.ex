defmodule KlassHeroWeb.Admin.Filters.IncidentCategoryFilter do
  @moduledoc false

  use Backpex.Filters.Boolean

  import Ecto.Query

  alias Backpex.Filters.Boolean
  alias KlassHero.Provider.IncidentReport

  @impl Backpex.Filter
  def label, do: "Category"

  # Options are derived from the entity so the list cannot drift from the enum.
  @impl Boolean
  def options(_assigns) do
    for category <- IncidentReport.valid_categories() do
      %{
        label: IncidentReport.category_label(category),
        key: Atom.to_string(category),
        predicate: dynamic([x], x.category == ^category)
      }
    end
  end
end
