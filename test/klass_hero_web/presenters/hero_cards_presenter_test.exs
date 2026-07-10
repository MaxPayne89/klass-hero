defmodule KlassHeroWeb.Presenters.HeroCardsPresenterTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Provider.StaffMember
  alias KlassHeroWeb.Presenters.HeroCardsPresenter

  @badge "Lead Instructor"

  defp staff(attrs) do
    %StaffMember{
      id: attrs[:id] || Ecto.UUID.generate(),
      provider_id: "prov-1",
      first_name: attrs[:first_name] || "First",
      last_name: attrs[:last_name] || "Last",
      role: attrs[:role],
      bio: attrs[:bio],
      headshot_url: attrs[:headshot_url],
      tags: attrs[:tags] || [],
      qualifications: attrs[:qualifications] || []
    }
  end

  # A list of distinct-id staff members plus a lead choice that is EITHER one of
  # their ids OR nil OR an id absent from the list — the three shapes the presenter
  # must handle.
  defp staff_and_lead do
    gen all(
          raw_ids <- uniq_list_of(positive_integer(), min_length: 1, max_length: 6),
          lead <- member_of([nil, "absent-id" | Enum.map(raw_ids, &"staff-#{&1}")])
        ) do
      staff_members =
        Enum.map(raw_ids, fn n ->
          staff(id: "staff-#{n}", first_name: "First#{n}", role: "Role#{n}")
        end)

      {staff_members, lead}
    end
  end

  describe "for_program/2 — properties" do
    property "emits exactly one card per staff member, preserving the id set" do
      check all({staff_members, lead} <- staff_and_lead()) do
        cards = HeroCardsPresenter.for_program(staff_members, lead)

        assert length(cards) == length(staff_members)

        card_staff_ids = Enum.map(cards, &String.replace_prefix(&1.id, "hero-card-staff-", ""))
        assert Enum.sort(card_staff_ids) == staff_members |> Enum.map(& &1.id) |> Enum.sort()
      end
    end

    property "badges exactly the lead — and only when the lead is in the list" do
      check all({staff_members, lead} <- staff_and_lead()) do
        cards = HeroCardsPresenter.for_program(staff_members, lead)
        badged = Enum.filter(cards, &(&1.badge == @badge))
        lead_present? = lead != nil and Enum.any?(staff_members, &(&1.id == lead))

        if lead_present? do
          assert [only] = badged
          assert only.id == "hero-card-staff-#{lead}"
          assert hd(cards).id == only.id, "the lead card must render first"
        else
          assert badged == []
          assert Enum.all?(cards, &is_nil(&1.badge))
        end
      end
    end

    property "non-lead cards keep their input order" do
      check all({staff_members, lead} <- staff_and_lead()) do
        cards = HeroCardsPresenter.for_program(staff_members, lead)

        non_lead_ids =
          cards
          |> Enum.reject(&(&1.badge == @badge))
          |> Enum.map(& &1.id)

        expected =
          staff_members
          |> Enum.reject(&(&1.id == lead))
          |> Enum.map(&"hero-card-staff-#{&1.id}")

        assert non_lead_ids == expected
      end
    end
  end

  describe "for_program/2 — examples" do
    test "returns [] when there are no staff members" do
      assert HeroCardsPresenter.for_program([], nil) == []
    end

    test "the lead card renders first with the badge and the staff member's rich fields" do
      lead =
        staff(
          id: "lead-1",
          first_name: "Alice",
          last_name: "Lead",
          role: "Head Coach",
          bio: "10 years experience",
          tags: ["sports", "youth"],
          qualifications: ["UEFA B"]
        )

      other = staff(id: "staff-other", first_name: "Bob", last_name: "Helper", role: "Assistant")

      # Pass the lead second to prove promotion to the front is by flag, not order.
      assert [first, second] = HeroCardsPresenter.for_program([other, lead], "lead-1")

      assert first.id == "hero-card-staff-lead-1"
      assert first.badge == @badge
      assert first.name == "Alice Lead"
      assert first.role == "Head Coach"
      assert first.bio == "10 years experience"
      assert first.tags == ["sports", "youth"]
      assert first.qualifications == ["UEFA B"]

      assert second.id == "hero-card-staff-staff-other"
      assert is_nil(second.badge)
    end

    test "defaults to no lead when the second argument is omitted" do
      assert [card] = HeroCardsPresenter.for_program([staff(first_name: "Alice")])
      assert is_nil(card.badge)
    end
  end
end
