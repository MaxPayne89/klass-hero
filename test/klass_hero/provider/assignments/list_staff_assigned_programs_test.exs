defmodule KlassHero.Provider.Assignments.ListStaffAssignedProgramsTest do
  use KlassHero.DataCase, async: true

  import KlassHero.ProviderFixtures

  alias KlassHero.Provider

  describe "execute/2" do
    test "returns all programs when staff has no tags" do
      staff = staff_member_fixture(%{tags: []})
      programs = [%{category: "sports"}, %{category: "arts"}]

      result = Provider.list_assigned_programs(staff, programs)
      assert length(result) == 2
    end

    test "filters programs by staff tags" do
      staff = staff_member_fixture(%{tags: ["sports"]})
      programs = [%{category: "sports"}, %{category: "arts"}, %{category: "music"}]

      result = Provider.list_assigned_programs(staff, programs)
      assert length(result) == 1
      assert hd(result).category == "sports"
    end

    test "returns empty list when no programs match" do
      staff = staff_member_fixture(%{tags: ["music"]})
      programs = [%{category: "sports"}, %{category: "arts"}]

      assert Provider.list_assigned_programs(staff, programs) == []
    end

    test "returns empty list when programs list is empty" do
      staff = staff_member_fixture(%{tags: ["sports"]})

      assert Provider.list_assigned_programs(staff, []) == []
    end
  end
end
