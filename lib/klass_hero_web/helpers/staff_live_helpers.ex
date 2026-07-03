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
  alias KlassHero.Provider.StaffMember

  @doc """
  Loads the programs the staff member is currently assigned to, alongside a
  `MapSet` of their ids.

  Composes `ProgramCatalog.list_programs_for_provider/1` with
  `Provider.list_assigned_programs/2`, keeping the cross-context fetch out of
  the Provider bounded context.

  Returns `{assigned_programs, assigned_program_ids}`. The list is suitable
  for rendering staff-scoped streams; the `MapSet` lets callers gate
  per-program actions in constant time.
  """
  @spec load_assigned_programs(StaffMember.t()) ::
          {[ProgramListing.t()], MapSet.t(String.t())}
  def load_assigned_programs(%StaffMember{provider_id: provider_id} = staff_member) do
    all_programs = ProgramCatalog.list_programs_for_provider(provider_id)
    assigned = Provider.list_assigned_programs(staff_member, all_programs)
    {assigned, MapSet.new(assigned, & &1.id)}
  end
end
