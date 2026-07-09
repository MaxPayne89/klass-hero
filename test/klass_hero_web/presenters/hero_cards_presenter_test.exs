defmodule KlassHeroWeb.Presenters.HeroCardsPresenterTest do
  use ExUnit.Case, async: true

  alias KlassHero.Provider.StaffMember
  alias KlassHeroWeb.Presenters.HeroCardsPresenter

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

  describe "for_program/2" do
    test "returns [] when there are no staff members" do
      assert HeroCardsPresenter.for_program([], nil) == []
    end

    test "returns plain staff hero cards, no badge, when there is no lead" do
      s1 = staff(first_name: "Alice", last_name: "Smith")
      s2 = staff(first_name: "Bob", last_name: "Jones")

      result = HeroCardsPresenter.for_program([s1, s2], nil)

      assert Enum.map(result, & &1.name) == ["Alice Smith", "Bob Jones"]
      assert Enum.all?(result, &is_nil(&1.badge))
    end

    test "renders the lead card first with the Lead Instructor badge" do
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

      # Pass the lead second to prove it is promoted to the front regardless of order.
      result = HeroCardsPresenter.for_program([other, lead], "lead-1")

      assert [first, second] = result

      assert first.id == "hero-card-staff-lead-1"
      assert first.badge == "Lead Instructor"
      assert first.name == "Alice Lead"
      assert first.role == "Head Coach"
      assert first.bio == "10 years experience"
      assert first.tags == ["sports", "youth"]
      assert first.qualifications == ["UEFA B"]

      assert second.id == "hero-card-staff-staff-other"
      assert is_nil(second.badge)
      assert second.role == "Assistant"
    end

    test "returns a single badged card when the lead is the only staff member" do
      lead = staff(id: "solo", first_name: "Marie", last_name: "Curie")

      assert [card] = HeroCardsPresenter.for_program([lead], "solo")
      assert card.id == "hero-card-staff-solo"
      assert card.badge == "Lead Instructor"
    end

    test "leaves every card unbadged when the lead id matches no staff member" do
      s1 = staff(id: "s1")
      s2 = staff(id: "s2")

      result = HeroCardsPresenter.for_program([s1, s2], "not-present")

      assert Enum.map(result, & &1.id) == ["hero-card-staff-s1", "hero-card-staff-s2"]
      assert Enum.all?(result, &is_nil(&1.badge))
    end

    test "defaults to no lead when the second argument is omitted" do
      s1 = staff(first_name: "Alice", last_name: "Smith")

      assert [card] = HeroCardsPresenter.for_program([s1])
      assert is_nil(card.badge)
    end
  end
end
