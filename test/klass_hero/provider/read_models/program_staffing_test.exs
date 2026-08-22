defmodule KlassHero.Provider.ReadModels.ProgramStaffingTest do
  use ExUnit.Case, async: true

  alias KlassHero.Provider.ReadModels.ProgramStaffing

  @lead_id "11111111-1111-1111-1111-111111111111"
  @other_id "22222222-2222-2222-2222-222222222222"
  @stranger_id "33333333-3333-3333-3333-333333333333"

  defp staffing(member_ids, lead_id) do
    %ProgramStaffing{
      program_id: "program-1",
      lead: lead_id && %{id: lead_id, name: "Lead Person", headshot_url: nil},
      member_ids: member_ids,
      member_count: length(member_ids)
    }
  end

  describe "staffed_by?/2" do
    # The lead is one of the members, so the predicate never needs a
    # "lead or member?" branch — that is the whole point of member_ids
    # carrying everyone.
    @cases [
      {"the lead", [@lead_id, @other_id], @lead_id, @lead_id, true},
      {"a non-lead member", [@lead_id, @other_id], @lead_id, @other_id, true},
      {"a member of a leaderless program", [@other_id], nil, @other_id, true},
      {"someone not on the program", [@lead_id], @lead_id, @stranger_id, false},
      {"anyone, when nobody is on the program", [], nil, @lead_id, false}
    ]

    for {label, member_ids, lead_id, queried_id, expected} <- @cases do
      test "matches #{label}" do
        actual = ProgramStaffing.staffed_by?(staffing(unquote(member_ids), unquote(lead_id)), unquote(queried_id))

        assert actual == unquote(expected),
               "expected staffed_by?(#{inspect(unquote(member_ids))}, #{inspect(unquote(queried_id))}) " <>
                 "to be #{unquote(expected)}, got #{actual}"
      end
    end

    test "a nil staffing (program absent from the batch read) is staffed by nobody" do
      refute ProgramStaffing.staffed_by?(nil, @lead_id)
    end
  end

  describe "empty/1" do
    test "builds the zero-staff value callers default to" do
      assert %ProgramStaffing{
               program_id: "program-1",
               lead: nil,
               member_ids: [],
               member_count: 0
             } = ProgramStaffing.empty("program-1")
    end
  end
end
