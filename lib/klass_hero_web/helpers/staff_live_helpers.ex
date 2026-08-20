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
