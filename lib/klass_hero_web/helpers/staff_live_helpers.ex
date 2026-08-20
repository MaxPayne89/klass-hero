defmodule KlassHeroWeb.Helpers.StaffLiveHelpers do
  @moduledoc """
  Shared lookups for staff-scoped LiveViews.

  Centralizes the provider-programs-plus-assignment-filter pattern so every
  staff LiveView mount derives the staff member's assigned programs the same
  way.
  """

  alias KlassHero.ProgramCatalog
  alias KlassHero.ProgramCatalog.Program
  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.ReadModels.StaffProgramAccess
  alias KlassHero.Provider.StaffMember

  @doc """
  Loads the programs the staff member is assigned to — split into the ones they
  may act on and the **Closed** ones they may only be shown (#1082) — alongside
  the `StaffProgramAccess` that decided the split.

  Fetches the write rows the assignments name rather than listing the provider's
  whole catalogue and filtering it down: a staff member on three of two hundred
  programs costs three rows. That also keeps this path off the `program_listings`
  projection entirely — display may lag, authorization may not, and here the two
  are the same fetch.

  Still narrowed to the staff member's own provider. `get_programs_by_ids/1` is
  not provider-scoped, and an assignment row naming another provider's program
  must not put it on this dashboard.
  """
  @spec load_assigned_programs(StaffMember.t()) ::
          {open :: [Program.t()], closed :: [Program.t()], StaffProgramAccess.t()}
  def load_assigned_programs(%StaffMember{provider_id: provider_id, id: staff_member_id}) do
    access = Provider.get_staff_program_access(staff_member_id)

    programs =
      access.program_ids
      |> MapSet.union(access.closed_program_ids)
      |> MapSet.to_list()
      |> ProgramCatalog.get_programs_by_ids()
      |> Enum.filter(&(&1.provider_id == provider_id))
      |> Enum.sort_by(& &1.title)

    {open, closed} = Enum.split_with(programs, &StaffProgramAccess.authorized?(access, &1.id))

    {open, closed, access}
  end

  @doc """
  Every program the provider runs, as `%{program_id => title}`.

  For naming rows that were let through on a session-grain gate (#783): a staff
  member covering a single session has no assignment to the program behind it, so
  a titles map built from assignments would come up empty for exactly the row the
  override put on screen. Titles carry no access — the caller has already decided
  what to render — so scoping this to the provider is the honest boundary.
  """
  @spec provider_program_names(String.t()) :: %{optional(String.t()) => String.t()}
  def provider_program_names(provider_id) when is_binary(provider_id) do
    provider_id
    |> ProgramCatalog.list_programs_for_provider()
    |> Map.new(&{&1.id, &1.title})
  end
end
