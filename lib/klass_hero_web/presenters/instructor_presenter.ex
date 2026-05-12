defmodule KlassHeroWeb.Presenters.InstructorPresenter do
  @moduledoc """
  Transforms a Program's `Instructor` value object into the prop shape consumed by
  `KlassHeroWeb.ProgramComponents.hero_card/1`.

  The Instructor value object is intentionally thin (id, name, optional headshot).
  This presenter widens it into the same prop shape the staff-member card uses,
  filling rich fields with `nil` / `[]` and tagging the card with a "Lead Instructor"
  badge so it is visually distinguished from staff cards.
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHero.ProgramCatalog.Domain.Models.Instructor

  @spec to_hero_card(Instructor.t() | nil) :: map() | nil
  def to_hero_card(nil), do: nil

  def to_hero_card(%Instructor{} = instructor) do
    %{
      id: "hero-card-instructor-#{instructor.id}",
      name: instructor.name,
      initials: initials_from_name(instructor.name),
      headshot_url: instructor.headshot_url,
      role: nil,
      bio: nil,
      tags: [],
      qualifications: [],
      badge: gettext("Lead Instructor")
    }
  end

  defp initials_from_name(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", fn token -> token |> String.first() |> String.upcase() end)
  end
end
