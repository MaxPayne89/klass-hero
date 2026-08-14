defmodule KlassHeroWeb.Helpers.StaffLiveHelpers do
  @moduledoc """
  Shared lookups for staff-scoped LiveViews.

  Centralizes the provider-programs-plus-assignment-filter pattern so every
  staff LiveView mount derives the staff member's assigned programs the same
  way.
  """

  alias KlassHero.ProgramCatalog
  alias KlassHero.ProgramCatalog.ProgramListing
  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.ReadModels.StaffProgramAccess
  alias KlassHero.Provider.StaffMember

  @doc """
  Loads the programs the staff member is assigned to, alongside the
  `StaffProgramAccess` that says which programs they may act on.

  Composes `ProgramCatalog.list_programs_for_provider/1` with
  `Provider.get_staff_program_access/1`, keeping the cross-context fetch out of
  the Provider bounded context.

  The returned access comes from the assignment rows, **not** from the filtered
  program list. Listings are read from the `provider_programs` projection, so
  deriving the gate from them would let projection lag revoke access to a program
  assigned moments ago: display may lag, authorization may not.
  """
  @spec load_assigned_programs(StaffMember.t()) ::
          {[ProgramListing.t()], StaffProgramAccess.t()}
  def load_assigned_programs(%StaffMember{provider_id: provider_id, id: staff_member_id}) do
    access = Provider.get_staff_program_access(staff_member_id)

    programs =
      provider_id
      |> ProgramCatalog.list_programs_for_provider()
      |> Enum.filter(&StaffProgramAccess.authorized?(access, &1.id))

    {programs, access}
  end
end
