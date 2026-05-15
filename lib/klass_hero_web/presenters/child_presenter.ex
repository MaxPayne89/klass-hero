defmodule KlassHeroWeb.Presenters.ChildPresenter do
  @moduledoc """
  Presentation layer for transforming Child domain models to UI-ready formats.

  This module follows the DDD/Ports & Adapters pattern by keeping presentation
  concerns in the web layer while the domain model stays pure.

  ## Usage

      alias KlassHeroWeb.Presenters.ChildPresenter

      # For simple views (booking dropdown)
      children_for_view = Enum.map(children, &ChildPresenter.to_simple_view/1)

      # For extended views with enrichment data (dashboard cards)
      enrichment = %{sessions: "8/10", progress: 80, activities: ["Art"]}
      children_for_view = Enum.map(children, &ChildPresenter.to_extended_view(&1, enrichment))
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHero.Family.Domain.Models.Child
  alias KlassHero.Shared.NameUtils

  @doc """
  Transforms a Child domain model to a simple view format.

  Used for contexts where only basic child information is needed,
  such as dropdown selections in booking forms.

  Returns a map with: id, name, age
  """
  def to_simple_view(%Child{} = child) do
    %{
      id: child.id,
      name: Child.full_name(child),
      age: calculate_age(child.date_of_birth)
    }
  end

  @doc """
  Transforms a Child domain model to an extended view format.

  When enrichment_data is provided (from Progress Tracking context),
  merges additional fields into the view.

  ## Parameters
    - child: A Child domain model
    - enrichment_data: Optional map with additional data (default: %{})

  ## Example enrichment_data
      %{
        sessions: "8/10",
        progress: 80,
        activities: ["Art", "Chess"]
      }

  Returns a map with: id, name, age, plus any enrichment fields
  """
  def to_extended_view(%Child{} = child, enrichment_data \\ %{}) do
    child
    |> to_simple_view()
    |> Map.merge(enrichment_data)
  end

  @doc """
  Transforms a Child domain model to a profile view format.

  Used for horizontal scrollable profile cards that display child's
  initials in a circular avatar, along with name and age.

  Returns a map with: id, name, age, initials
  """
  def to_profile_view(%Child{} = child) do
    %{
      id: child.id,
      name: Child.full_name(child),
      age: calculate_age(child.date_of_birth),
      initials: NameUtils.initials_from_name(Child.full_name(child))
    }
  end

  @doc """
  Generates a human-readable summary of children for display in settings.

  Returns a comma-separated string of "Name (age)" pairs, or a localized
  "No children yet" message for an empty list.

  ## Examples

      children_summary([])
      #=> "No children yet"

      children_summary([%Child{first_name: "Emma", last_name: "Smith", ...}])
      #=> "Emma Smith (7)"
  """
  def children_summary([]), do: gettext("No children yet")

  def children_summary(children) when is_list(children) do
    Enum.map_join(children, ", ", fn child ->
      view = to_simple_view(child)
      "#{view.name} (#{view.age})"
    end)
  end

  defp calculate_age(date_of_birth) do
    today = Date.utc_today()
    years = today.year - date_of_birth.year

    if Date.after?(
         Date.new!(today.year, date_of_birth.month, date_of_birth.day),
         today
       ) do
      years - 1
    else
      years
    end
  end
end
