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

  alias KlassHero.Provider.StaffMember
  alias KlassHeroWeb.Presenters.StaffMemberPresenter

  @spec for_panel([StaffMember.t()], String.t() | nil) :: [map()]
  def for_panel(staff_members, lead_id \\ nil) when is_list(staff_members) do
    {leads, others} = Enum.split_with(staff_members, &lead?(&1, lead_id))

    Enum.map(leads, &to_row(&1, true)) ++ Enum.map(others, &to_row(&1, false))
  end

  defp to_row(%StaffMember{} = staff, lead?) do
    staff
    |> StaffMemberPresenter.to_card_view()
    |> Map.put(:lead?, lead?)
  end

  defp lead?(_staff, nil), do: false
  defp lead?(%StaffMember{id: id}, lead_id), do: id == lead_id
end
