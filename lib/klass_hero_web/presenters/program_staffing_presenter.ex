defmodule KlassHeroWeb.Presenters.ProgramStaffingPresenter do
  @moduledoc """
  Builds the rows rendered by the provider's program-staffing panel.

  Same two inputs as `HeroCardsPresenter.for_program/2` — the program's assigned
  staff, and which of them carries `is_lead_instructor` — but shaped for
  management rather than for the public "Meet the Heroes" section: rows keep the
  bare staff id that the panel's actions post back, and carry `lead?` so the
  template never re-derives leadership by comparing ids.

  Two presenters rather than one shared read model on purpose: the hero cards
  need bio and qualifications, this needs none of that and does need the raw id.
  """

  alias KlassHero.Provider
  alias KlassHero.Provider.StaffMember
  alias KlassHeroWeb.Presenters.StaffMemberPresenter

  @spec for_panel([StaffMember.t()], String.t() | nil) :: [map()]
  def for_panel(staff_members, lead_id \\ nil) when is_list(staff_members) do
    {leads, others} = Enum.split_with(staff_members, &lead?(&1, lead_id))

    Enum.map(leads, &to_row(&1, true)) ++ Enum.map(others, &to_row(&1, false))
  end

  @doc """
  The `{label, id}` pairs behind a staffing panel's "add someone" picker.

  Beside `for_panel/2` because it answers the same question — how a staff member
  is named in this panel — for the other half of the same screen. Held apart from
  the rows because a picker needs no card view, only a label.
  """
  @spec assignable_options([StaffMember.t()]) :: [{String.t(), String.t()}]
  def assignable_options(staff_members) when is_list(staff_members) do
    for member <- staff_members, do: {Provider.staff_member_full_name(member), member.id}
  end

  defp to_row(%StaffMember{} = staff, lead?) do
    staff
    |> StaffMemberPresenter.to_card_view()
    |> Map.put(:lead?, lead?)
  end

  defp lead?(_staff, nil), do: false
  defp lead?(%StaffMember{id: id}, lead_id), do: id == lead_id
end
