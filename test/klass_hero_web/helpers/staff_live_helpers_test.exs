defmodule KlassHeroWeb.Helpers.StaffLiveHelpersTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory
  import KlassHero.ProviderFixtures

  alias KlassHero.Provider.ReadModels.StaffProgramAccess
  alias KlassHeroWeb.Helpers.StaffLiveHelpers

  # The listing row is no longer what this helper reads — it fetches the write
  # rows its assignments name (#1082) — but it is still inserted here so these
  # tests keep exercising the shape the rest of the staff surfaces see.
  defp program(provider, category, attrs \\ []) do
    attrs = Keyword.merge([provider_id: provider.id, category: category], attrs)
    program = insert(:program_schema, attrs)
    program
  end

  defp assign(program, staff) do
    program_assignment_fixture(%{
      provider_id: program.provider_id,
      program_id: program.id,
      staff_member_id: staff.id
    })
  end

  describe "load_assigned_programs/1" do
    test "shows a program the staff member is assigned to even when it is outside their Specialties" do
      provider = provider_profile_fixture()
      staff = staff_member_fixture(provider_id: provider.id, tags: ["sports"])
      arts_program = program(provider, "arts")

      assign(arts_program, staff)

      {open, closed, access} = StaffLiveHelpers.load_assigned_programs(staff)

      assert Enum.map(open, & &1.id) == [arts_program.id]
      assert closed == []
      assert StaffProgramAccess.authorized?(access, arts_program.id)
    end

    test "hides a provider program the staff member is not assigned to, whatever their Specialties" do
      provider = provider_profile_fixture()
      staff = staff_member_fixture(provider_id: provider.id, tags: [])
      sports_program = program(provider, "sports")

      {open, closed, access} = StaffLiveHelpers.load_assigned_programs(staff)

      assert open == []
      assert closed == []
      refute StaffProgramAccess.authorized?(access, sports_program.id)
    end

    # Defence in depth, not a reachable state: `assign_staff_to_program/1` proves
    # ownership of both the staff member and the program before inserting, so only
    # a fixture (or the facade-bypassing seed script) can build this row. Nothing
    # in the database enforces it, and this is the surface where such a row would
    # become a child's roster — so the exclusion is asserted rather than assumed.
    test "excludes an assigned program belonging to another provider" do
      provider = provider_profile_fixture()
      other_provider = provider_profile_fixture()
      staff = staff_member_fixture(provider_id: provider.id, tags: [])
      own = program(provider, "sports")
      foreign = program(other_provider, "sports")

      for p <- [own, foreign], do: assign(p, staff)

      {open, closed, _access} = StaffLiveHelpers.load_assigned_programs(staff)

      assert Enum.map(open, & &1.id) == [own.id]
      # And not merely absent from the actionable list: a foreign program must not
      # be rendered in the read-only "Completed" section either.
      refute foreign.id in Enum.map(closed, & &1.id)
    end

    test "returns no programs and an empty access when the provider has none" do
      provider = provider_profile_fixture()
      staff = staff_member_fixture(provider_id: provider.id, tags: [])

      assert {[], [], %StaffProgramAccess{program_ids: program_ids}} =
               StaffLiveHelpers.load_assigned_programs(staff)

      assert MapSet.size(program_ids) == 0
    end

    test "orders each list by title" do
      provider = provider_profile_fixture()
      staff = staff_member_fixture(provider_id: provider.id, tags: [])
      zebra = program(provider, "sports", title: "Zebra")
      alpha = program(provider, "sports", title: "Alpha")

      for p <- [zebra, alpha], do: assign(p, staff)

      {open, _closed, _access} = StaffLiveHelpers.load_assigned_programs(staff)

      assert Enum.map(open, & &1.title) == ["Alpha", "Zebra"]
    end
  end

  describe "load_assigned_programs/1 and Closed Programs (#1082)" do
    setup do
      provider = provider_profile_fixture()
      staff = staff_member_fixture(provider_id: provider.id, tags: [])

      %{provider: provider, staff: staff}
    end

    test "splits the roster into open and closed", %{provider: provider, staff: staff} do
      open = program(provider, "sports", title: "Still Running")
      closed = program(provider, "arts", title: "Last Spring", end_date: Date.add(Date.utc_today(), -20))

      for p <- [open, closed], do: assign(p, staff)

      {open_programs, closed_programs, _access} = StaffLiveHelpers.load_assigned_programs(staff)

      assert Enum.map(open_programs, & &1.id) == [open.id]
      assert Enum.map(closed_programs, & &1.id) == [closed.id]
    end

    test "keeps a program inside its grace window open", %{provider: provider, staff: staff} do
      recent = program(provider, "sports", end_date: Date.add(Date.utc_today(), -2))

      assign(recent, staff)

      {open_programs, closed_programs, _access} = StaffLiveHelpers.load_assigned_programs(staff)

      assert Enum.map(open_programs, & &1.id) == [recent.id]
      assert closed_programs == []
    end

    test "still names a closed program, so it can be listed read-only", %{provider: provider, staff: staff} do
      closed = program(provider, "arts", title: "Autumn Club", end_date: Date.add(Date.utc_today(), -60))

      assign(closed, staff)

      {_open, [listed], _access} = StaffLiveHelpers.load_assigned_programs(staff)

      assert listed.title == "Autumn Club"
      assert listed.category == "arts"
    end
  end
end
