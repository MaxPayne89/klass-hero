defmodule KlassHeroWeb.Presenters.InstructorPresenter do
  @moduledoc """
  Transforms a Program's `Instructor` value object into the prop shape consumed by
  `KlassHeroWeb.ProgramComponents.hero_card/1`.

  Pure transform — no badge or i18n logic. The `Lead Instructor` semantic is
  applied by `KlassHeroWeb.Presenters.HeroCardsPresenter`, which is the only
  caller of this module.
  """

  alias KlassHero.ProgramCatalog.Domain.Models.Instructor

  @spec to_hero_card(Instructor.t() | nil) :: map() | nil
  def to_hero_card(nil), do: nil

  def to_hero_card(%Instructor{} = instructor) do
    %{
      id: "hero-card-instructor-#{instructor.id}",
      name: instructor.name,
      initials: Instructor.initials(instructor),
      headshot_url: instructor.headshot_url,
      role: nil,
      bio: nil,
      tags: [],
      qualifications: [],
      badge: nil
    }
  end
end
