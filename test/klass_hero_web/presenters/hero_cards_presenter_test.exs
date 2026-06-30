defmodule KlassHeroWeb.Presenters.HeroCardsPresenterTest do
  use ExUnit.Case, async: true

  alias KlassHero.ProgramCatalog.Instructor
  alias KlassHero.Provider.Domain.Models.StaffMember
  alias KlassHeroWeb.Presenters.HeroCardsPresenter

  defp staff(attrs) do
    base = %StaffMember{
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

    base
  end

  defp instructor(id, name) do
    %Instructor{id: id, name: name, headshot_url: nil}
  end

  describe "for_program/2" do
    test "returns [] when instructor is nil and staff is empty" do
      assert HeroCardsPresenter.for_program(nil, []) == []
    end

    test "returns plain staff hero cards when instructor is nil" do
      s1 = staff(first_name: "Alice", last_name: "Smith")
      s2 = staff(first_name: "Bob", last_name: "Jones")

      result = HeroCardsPresenter.for_program(nil, [s1, s2])

      assert length(result) == 2
      assert Enum.map(result, & &1.name) == ["Alice Smith", "Bob Jones"]
      assert Enum.all?(result, &is_nil(&1.badge))
    end

    test "returns single instructor card when no staff are assigned" do
      i = instructor("inst-id-1", "Marie Curie")

      result = HeroCardsPresenter.for_program(i, [])

      assert [card] = result
      assert card.id == "hero-card-instructor-inst-id-1"
      assert card.name == "Marie Curie"
      assert card.badge == "Lead Instructor"
    end

    test "puts instructor card first when no staff id matches the instructor" do
      i = instructor("inst-id-2", "Marie Curie")
      s1 = staff(id: "staff-1", first_name: "Coach", last_name: "Smith", role: "Assistant")
      s2 = staff(id: "staff-2", first_name: "Coach", last_name: "Brown")

      result = HeroCardsPresenter.for_program(i, [s1, s2])

      assert length(result) == 3

      assert Enum.map(result, & &1.id) == [
               "hero-card-instructor-inst-id-2",
               "hero-card-staff-staff-1",
               "hero-card-staff-staff-2"
             ]

      [instructor_card | _] = result
      assert instructor_card.badge == "Lead Instructor"
    end

    test "merges into single card when instructor.id matches a staff member's id" do
      shared_id = "shared-uuid-42"
      i = instructor(shared_id, "Alice Lead")

      lead =
        staff(
          id: shared_id,
          first_name: "Alice",
          last_name: "Lead",
          role: "Head Coach",
          bio: "10 years experience",
          tags: ["sports", "youth"],
          qualifications: ["UEFA B"]
        )

      other = staff(id: "staff-other", first_name: "Bob", last_name: "Helper", role: "Assistant")

      result = HeroCardsPresenter.for_program(i, [lead, other])

      assert length(result) == 2

      [first, second] = result

      # First card: the merged "lead" — staff DOM id, badge attached, rich fields preserved
      assert first.id == "hero-card-staff-#{shared_id}"
      assert first.badge == "Lead Instructor"
      assert first.role == "Head Coach"
      assert first.bio == "10 years experience"
      assert first.tags == ["sports", "youth"]
      assert first.qualifications == ["UEFA B"]
      assert first.name == "Alice Lead"

      # Second card: the other staff, unchanged
      assert second.id == "hero-card-staff-staff-other"
      assert is_nil(second.badge)
      assert second.role == "Assistant"
    end
  end
end
