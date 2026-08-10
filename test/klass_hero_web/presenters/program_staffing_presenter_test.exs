defmodule KlassHeroWeb.Presenters.ProgramStaffingPresenterTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Provider.StaffMember
  alias KlassHeroWeb.Presenters.ProgramStaffingPresenter

  defp staff(attrs) do
    %StaffMember{
      id: attrs[:id] || Ecto.UUID.generate(),
      provider_id: "prov-1",
      first_name: attrs[:first_name] || "First",
      last_name: attrs[:last_name] || "Last",
      role: attrs[:role],
      email: attrs[:email],
      headshot_url: attrs[:headshot_url],
      active: true,
      tags: [],
      qualifications: []
    }
  end

  # Mirrors HeroCardsPresenterTest's generator: the lead is EITHER one of the
  # listed ids, OR nil, OR an id absent from the list — the three shapes a panel
  # can be handed (no lead set, lead present, lead already gone).
  defp staff_and_lead do
    # `integer(1..1_000)`, not `positive_integer()`: a bounded domain keeps
    # `uniq_list_of` from starving on small early sizes.
    gen all(
          raw_ids <- uniq_list_of(integer(1..1_000), min_length: 1, max_length: 6),
          lead <- member_of([nil, "absent-id" | Enum.map(raw_ids, &"staff-#{&1}")])
        ) do
      members = Enum.map(raw_ids, fn n -> staff(id: "staff-#{n}", first_name: "First#{n}") end)

      {members, lead}
    end
  end

  describe "for_panel/2 — properties" do
    property "emits exactly one row per staff member, preserving the id set" do
      check all({members, lead} <- staff_and_lead()) do
        rows = ProgramStaffingPresenter.for_panel(members, lead)

        assert length(rows) == length(members)
        assert Enum.sort(Enum.map(rows, & &1.id)) == members |> Enum.map(& &1.id) |> Enum.sort()
      end
    end

    property "flags exactly the lead, and only when the lead is on the program" do
      check all({members, lead} <- staff_and_lead()) do
        rows = ProgramStaffingPresenter.for_panel(members, lead)
        flagged = Enum.filter(rows, & &1.lead?)
        lead_present? = lead != nil and Enum.any?(members, &(&1.id == lead))

        if lead_present? do
          assert [only] = flagged
          assert only.id == lead
          assert hd(rows).id == lead, "the lead must render first"
        else
          assert flagged == []
        end
      end
    end

    property "non-lead rows keep their input order" do
      check all({members, lead} <- staff_and_lead()) do
        actual =
          members
          |> ProgramStaffingPresenter.for_panel(lead)
          |> Enum.reject(& &1.lead?)
          |> Enum.map(& &1.id)

        expected = members |> Enum.map(& &1.id) |> Enum.reject(&(&1 == lead))

        assert actual == expected
      end
    end
  end

  describe "for_panel/2" do
    test "moves the lead to the front and flags them" do
      [a, b, c] =
        members = [
          staff(id: "a", first_name: "Ann"),
          staff(id: "b", first_name: "Bo"),
          staff(id: "c", first_name: "Cy")
        ]

      assert [first, second, third] = ProgramStaffingPresenter.for_panel(members, b.id)

      assert {first.id, first.lead?} == {b.id, true}
      assert {second.id, second.lead?} == {a.id, false}
      assert {third.id, third.lead?} == {c.id, false}
    end

    test "carries the display fields the panel renders" do
      member = staff(id: "a", first_name: "Ann", last_name: "Blake", role: "Coach")

      assert [row] = ProgramStaffingPresenter.for_panel([member], nil)

      assert row.full_name == "Ann Blake"
      assert row.initials == "AB"
      assert row.role == "Coach"
      assert Map.has_key?(row, :headshot_url)
    end

    test "returns an empty list for a program with nobody on it" do
      assert ProgramStaffingPresenter.for_panel([], nil) == []
      assert ProgramStaffingPresenter.for_panel([], "some-id") == []
    end
  end
end
