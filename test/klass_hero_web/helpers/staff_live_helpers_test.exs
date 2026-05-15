defmodule KlassHeroWeb.Helpers.StaffLiveHelpersTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.ProviderFixtures
  alias KlassHeroWeb.Helpers.StaffLiveHelpers

  describe "load_assigned_programs/1" do
    test "returns all provider programs and a MapSet of every program id when staff has no tags" do
      provider = ProviderFixtures.provider_profile_fixture()
      staff_member = ProviderFixtures.staff_member_fixture(provider_id: provider.id, tags: [])

      program_a =
        insert(:program_listing_schema, provider_id: provider.id, category: "sports")

      program_b =
        insert(:program_listing_schema, provider_id: provider.id, category: "arts")

      {programs, assigned_ids} = StaffLiveHelpers.load_assigned_programs(staff_member)

      assert Enum.map(programs, & &1.id) |> Enum.sort() ==
               Enum.sort([program_a.id, program_b.id])

      assert assigned_ids == MapSet.new([program_a.id, program_b.id])
    end

    test "MapSet contains only category-matched program ids when staff has tags" do
      provider = ProviderFixtures.provider_profile_fixture()

      staff_member =
        ProviderFixtures.staff_member_fixture(provider_id: provider.id, tags: ["sports"])

      sports_program =
        insert(:program_listing_schema, provider_id: provider.id, category: "sports")

      arts_program =
        insert(:program_listing_schema, provider_id: provider.id, category: "arts")

      {programs, assigned_ids} = StaffLiveHelpers.load_assigned_programs(staff_member)

      assert Enum.map(programs, & &1.id) |> Enum.sort() ==
               Enum.sort([sports_program.id, arts_program.id])

      assert assigned_ids == MapSet.new([sports_program.id])
    end

    test "returns an empty list and empty MapSet when provider has no programs" do
      provider = ProviderFixtures.provider_profile_fixture()
      staff_member = ProviderFixtures.staff_member_fixture(provider_id: provider.id, tags: [])

      assert {[], assigned_ids} = StaffLiveHelpers.load_assigned_programs(staff_member)
      assert MapSet.size(assigned_ids) == 0
    end

    test "excludes programs from other providers" do
      provider = ProviderFixtures.provider_profile_fixture()
      other_provider = ProviderFixtures.provider_profile_fixture()
      staff_member = ProviderFixtures.staff_member_fixture(provider_id: provider.id, tags: [])

      own_program = insert(:program_listing_schema, provider_id: provider.id, category: "sports")
      _foreign = insert(:program_listing_schema, provider_id: other_provider.id, category: "sports")

      {programs, assigned_ids} = StaffLiveHelpers.load_assigned_programs(staff_member)

      assert Enum.map(programs, & &1.id) == [own_program.id]
      assert assigned_ids == MapSet.new([own_program.id])
    end
  end
end
