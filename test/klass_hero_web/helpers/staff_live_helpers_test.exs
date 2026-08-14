defmodule KlassHeroWeb.Helpers.StaffLiveHelpersTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory
  import KlassHero.ProviderFixtures

  alias KlassHero.Provider.Domain.ReadModels.StaffProgramAccess
  alias KlassHeroWeb.Helpers.StaffLiveHelpers

  # The write row backs ownership checks; the listing row is what
  # `ProgramCatalog.list_programs_for_provider/1` reads, and it only matches when
  # the two share an id (the projection would normally keep them in step).
  defp program(provider, category) do
    program = insert(:program_schema, provider_id: provider.id, category: category)
    insert(:program_listing_schema, id: program.id, provider_id: provider.id, category: category)
    program
  end

  describe "load_assigned_programs/1" do
    test "shows a program the staff member is assigned to even when it is outside their Specialties" do
      provider = provider_profile_fixture()
      staff = staff_member_fixture(provider_id: provider.id, tags: ["sports"])
      arts_program = program(provider, "arts")

      program_assignment_fixture(%{
        provider_id: provider.id,
        program_id: arts_program.id,
        staff_member_id: staff.id
      })

      {programs, access} = StaffLiveHelpers.load_assigned_programs(staff)

      assert Enum.map(programs, & &1.id) == [arts_program.id]
      assert StaffProgramAccess.authorized?(access, arts_program.id)
    end

    test "hides a provider program the staff member is not assigned to, whatever their Specialties" do
      provider = provider_profile_fixture()
      staff = staff_member_fixture(provider_id: provider.id, tags: [])
      sports_program = program(provider, "sports")

      {programs, access} = StaffLiveHelpers.load_assigned_programs(staff)

      assert programs == []
      refute StaffProgramAccess.authorized?(access, sports_program.id)
    end

    test "excludes an assigned program belonging to another provider" do
      provider = provider_profile_fixture()
      other_provider = provider_profile_fixture()
      staff = staff_member_fixture(provider_id: provider.id, tags: [])
      own = program(provider, "sports")
      foreign = program(other_provider, "sports")

      for p <- [own, foreign] do
        program_assignment_fixture(%{
          provider_id: p.provider_id,
          program_id: p.id,
          staff_member_id: staff.id
        })
      end

      {programs, _access} = StaffLiveHelpers.load_assigned_programs(staff)

      assert Enum.map(programs, & &1.id) == [own.id]
    end

    test "returns no programs and an empty access when the provider has none" do
      provider = provider_profile_fixture()
      staff = staff_member_fixture(provider_id: provider.id, tags: [])

      assert {[], %StaffProgramAccess{program_ids: program_ids}} =
               StaffLiveHelpers.load_assigned_programs(staff)

      assert MapSet.size(program_ids) == 0
    end
  end
end
