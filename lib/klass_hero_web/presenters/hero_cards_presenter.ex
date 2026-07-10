defmodule KlassHeroWeb.Presenters.HeroCardsPresenter do
  @moduledoc """
  Assembles the ordered list of hero-card prop maps rendered in the "Meet the Heroes"
  section of the program detail page.

  There is a single data source: the program's assigned staff members (rows in
  `program_staff_assignments`). The lead instructor is whichever assignment carries
  `is_lead_instructor` — passed in as `lead_id`. That card is rendered first with a
  "Lead Instructor" badge; the rest follow in their given order. No merge logic and
  no denormalized `Instructor` snapshot: the flag on the assignment is the single
  source of truth.
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHero.Provider.StaffMember
  alias KlassHeroWeb.Presenters.StaffMemberPresenter

  @spec for_program([StaffMember.t()], String.t() | nil) :: [map()]
  def for_program(staff_members, lead_id \\ nil) when is_list(staff_members) do
    {leads, others} = Enum.split_with(staff_members, &lead?(&1, lead_id))

    lead_cards =
      Enum.map(leads, fn staff ->
        staff
        |> StaffMemberPresenter.to_hero_card()
        |> Map.put(:badge, gettext("Lead Instructor"))
      end)

    lead_cards ++ StaffMemberPresenter.to_hero_card_list(others)
  end

  defp lead?(_staff, nil), do: false
  defp lead?(%StaffMember{id: id}, lead_id), do: id == lead_id
end
