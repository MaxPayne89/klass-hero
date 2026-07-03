defmodule KlassHeroWeb.Presenters.HeroCardsPresenter do
  @moduledoc """
  Assembles the ordered list of hero-card prop maps rendered in the "Meet the Heroes"
  section of the program detail page.

  Two data sources feed this list:

    * The program's `Instructor` value object (denormalized snapshot of one
      `staff_members` row — `programs.instructor_id` references `staff_members.id`).
    * The program's assigned staff members (rows in `program_staff_assignments`).

  When the same person appears in both sources (instructor.id == staff_member.id),
  a single merged card is rendered: the staff member's richer view (role, bio,
  tags, qualifications) is preserved and the "Lead Instructor" badge is applied
  on top. Otherwise the instructor card is rendered first and staff follow.
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHero.ProgramCatalog.Instructor
  alias KlassHero.Provider.StaffMember
  alias KlassHeroWeb.Presenters.InstructorPresenter
  alias KlassHeroWeb.Presenters.StaffMemberPresenter

  @spec for_program(Instructor.t() | nil, [StaffMember.t()]) :: [map()]
  def for_program(nil, staff_members) when is_list(staff_members) do
    StaffMemberPresenter.to_hero_card_list(staff_members)
  end

  def for_program(%Instructor{} = instructor, staff_members) when is_list(staff_members) do
    {matching, others} = Enum.split_with(staff_members, &(&1.id == instructor.id))

    lead_card =
      case matching do
        [lead | _] -> StaffMemberPresenter.to_hero_card(lead)
        [] -> InstructorPresenter.to_hero_card(instructor)
      end
      |> Map.put(:badge, gettext("Lead Instructor"))

    [lead_card | StaffMemberPresenter.to_hero_card_list(others)]
  end
end
