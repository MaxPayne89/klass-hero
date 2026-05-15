defmodule KlassHeroWeb.Helpers.StaffLiveHelpers do
  @moduledoc """
  Shared lookups for staff-scoped LiveViews.

  Centralizes the provider-programs-plus-assignment-filter pattern so every
  staff LiveView mount derives the staff member's assigned programs the same
  way.
  """

  alias KlassHero.ProgramCatalog
  alias KlassHero.ProgramCatalog.Domain.ReadModels.ProgramListing
  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.Models.StaffMember

  @doc """
  Loads all programs owned by the staff member's provider, alongside a
  `MapSet` of the program ids the staff member is currently assigned to.

  Composes `ProgramCatalog.list_programs_for_provider/1` with
  `Provider.list_assigned_programs/2`, keeping the cross-context fetch out of
  the Provider bounded context.

  Returns `{all_programs, assigned_program_ids}` so callers can both render
  the full list (e.g. dashboard streams) and check assignment membership in
  constant time.
  """
  @spec load_assigned_programs(StaffMember.t()) ::
          {[ProgramListing.t()], MapSet.t(String.t())}
  def load_assigned_programs(%StaffMember{provider_id: provider_id} = staff_member) do
    all_programs = ProgramCatalog.list_programs_for_provider(provider_id)
    assigned = Provider.list_assigned_programs(staff_member, all_programs)
    {all_programs, MapSet.new(assigned, & &1.id)}
  end
end
