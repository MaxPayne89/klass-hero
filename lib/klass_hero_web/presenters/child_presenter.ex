defmodule KlassHeroWeb.Presenters.ChildPresenter do
  @moduledoc """
  Transforms Child domain models to UI-ready formats.
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHero.Family.Domain.Models.Child
  alias KlassHero.Shared.NameUtils

  @doc """
  Simple view with id, name, age — used for booking dropdowns.
  """
  def to_simple_view(%Child{} = child) do
    %{
      id: child.id,
      name: Child.full_name(child),
      age: calculate_age(child.date_of_birth)
    }
  end

  @doc """
  Extended view merging simple view with optional enrichment data (e.g. sessions, progress).
  """
  def to_extended_view(%Child{} = child, enrichment_data \\ %{}) do
    child
    |> to_simple_view()
    |> Map.merge(enrichment_data)
  end

  @doc """
  Profile view with id, name, age, initials — used for horizontal profile cards.
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
