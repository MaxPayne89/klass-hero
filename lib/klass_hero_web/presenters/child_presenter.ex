defmodule KlassHeroWeb.Presenters.ChildPresenter do
  @moduledoc """
  Transforms Child domain models to UI-ready formats.
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHero.Family.Child
  alias KlassHero.Shared.NameUtils

  @doc """
  Simple view with id, name, age — used for booking dropdowns.
  """
  def to_simple_view(%Child{} = child) do
    %{
      id: child.id,
      name: Child.full_name(child),
      age: age_in_years(child.date_of_birth, Date.utc_today())
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
      age: age_in_years(child.date_of_birth, Date.utc_today()),
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

      # Interpolating a nil age renders "Emma Smith ()" — `to_string(nil)` is "".
      # Drop the parenthetical instead, the way format_birth_date/1 drops the date.
      if view.age, do: "#{view.name} (#{view.age})", else: view.name
    end)
  end

  @doc """
  Age in whole years from `date_of_birth` to `reference_date`.

  Returns nil for an unknown date of birth — a GDPR-anonymized child keeps its
  enrolments, so a roster can carry one.

  The reference date is a parameter rather than `Date.utc_today()` so callers
  that need a deterministic answer (tests, backdated reports) can supply one.
  """
  @spec age_in_years(Date.t() | nil, Date.t()) :: non_neg_integer() | nil
  def age_in_years(nil, _reference_date), do: nil

  def age_in_years(date_of_birth, reference_date) do
    years = reference_date.year - date_of_birth.year

    # Tuple comparison rather than Date.new!/3, which raises on a Feb-29 date of
    # birth in a non-leap reference year.
    if {reference_date.month, reference_date.day} < {date_of_birth.month, date_of_birth.day},
      do: years - 1,
      else: years
  end
end
