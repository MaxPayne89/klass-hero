defmodule KlassHeroWeb.Presenters.ChildPresenterTest do
  @moduledoc """
  Tests for ChildPresenter pure presentation functions.

  All functions under test are side-effect-free — no DB, no mocks needed.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Family.Domain.Models.Child
  alias KlassHeroWeb.Presenters.ChildPresenter

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp build_child(overrides \\ %{}) do
    defaults = %{
      id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      first_name: "Anna",
      last_name: "Müller",
      date_of_birth: years_ago(8)
    }

    struct!(Child, Map.merge(defaults, overrides))
  end

  # A fixed past date whose Jan 1 birthday is always in the past (regardless of today).
  defp birthday_in_past(n), do: Date.new!(Date.utc_today().year - n, 1, 1)

  # A fixed past date whose Dec 31 birthday is always in the future (regardless of today).
  defp birthday_in_future(n), do: Date.new!(Date.utc_today().year - n, 12, 31)

  # Returns a date exactly `n` years before today (birthday already passed this year).
  defp years_ago(n) do
    today = Date.utc_today()
    Date.new!(today.year - n, today.month, today.day)
  end

  # ---------------------------------------------------------------------------
  # to_simple_view/1
  # ---------------------------------------------------------------------------

  describe "to_simple_view/1" do
    test "returns map with id, name, and age" do
      child = build_child()
      result = ChildPresenter.to_simple_view(child)

      assert result.id == child.id
      assert result.name == "Anna Müller"
      assert is_integer(result.age)
    end

    test "computes age correctly when birthday has already occurred this year" do
      child = build_child(%{date_of_birth: birthday_in_past(10)})
      assert ChildPresenter.to_simple_view(child).age == 10
    end

    test "computes age correctly when birthday is still upcoming this year" do
      child = build_child(%{date_of_birth: birthday_in_future(10)})
      assert ChildPresenter.to_simple_view(child).age == 9
    end

    test "returns 0 for a child born this year" do
      child = build_child(%{date_of_birth: years_ago(0)})
      assert ChildPresenter.to_simple_view(child).age == 0
    end

    # birthday_in_past/1 pins the birthday to Jan 1 (always already passed this
    # year), so the computed age equals the generated number of years exactly.
    property "computes age as whole years elapsed for any past Jan-1 birthday" do
      check all(years <- StreamData.integer(0..18)) do
        child = build_child(%{date_of_birth: birthday_in_past(years)})
        assert ChildPresenter.to_simple_view(child).age == years
      end
    end
  end

  # ---------------------------------------------------------------------------
  # to_extended_view/2
  # ---------------------------------------------------------------------------

  describe "to_extended_view/2" do
    test "without enrichment returns the same fields as to_simple_view" do
      child = build_child()
      assert ChildPresenter.to_extended_view(child) == ChildPresenter.to_simple_view(child)
    end

    test "merges enrichment data into the simple view" do
      child = build_child()
      enrichment = %{sessions: "8/10", progress: 80, activities: ["Art", "Chess"]}

      result = ChildPresenter.to_extended_view(child, enrichment)

      assert result.id == child.id
      assert result.sessions == "8/10"
      assert result.progress == 80
      assert result.activities == ["Art", "Chess"]
    end

    test "enrichment fields overwrite base fields when keys collide" do
      child = build_child()
      result = ChildPresenter.to_extended_view(child, %{name: "Overridden"})

      assert result.name == "Overridden"
    end
  end

  # ---------------------------------------------------------------------------
  # to_profile_view/1
  # ---------------------------------------------------------------------------

  describe "to_profile_view/1" do
    test "returns id, name, age, and initials" do
      child = build_child()
      result = ChildPresenter.to_profile_view(child)

      assert Map.keys(result) |> Enum.sort() == [:age, :id, :initials, :name]
    end

    test "extracts two initials from a first and last name" do
      child = build_child(%{first_name: "Anna", last_name: "Müller"})
      assert ChildPresenter.to_profile_view(child).initials == "AM"
    end

    test "initials are uppercased" do
      child = build_child(%{first_name: "anna", last_name: "müller"})
      assert ChildPresenter.to_profile_view(child).initials == "AM"
    end

    test "takes at most two initials for a multi-word name" do
      child = build_child(%{first_name: "Anna Maria", last_name: "Müller"})
      # full_name is "Anna Maria Müller" — initials should be "AM" (first 2 tokens)
      result = ChildPresenter.to_profile_view(child)
      assert String.length(result.initials) == 2
      assert result.initials == "AM"
    end

    # The three views derive age from the same child; they must never disagree.
    property "to_simple_view and to_profile_view report the same age" do
      check all(years <- StreamData.integer(0..18)) do
        child = build_child(%{date_of_birth: birthday_in_past(years)})
        assert ChildPresenter.to_profile_view(child).age == ChildPresenter.to_simple_view(child).age
      end
    end
  end

  # ---------------------------------------------------------------------------
  # children_summary/1
  # ---------------------------------------------------------------------------

  describe "children_summary/1" do
    setup do
      Gettext.put_locale(KlassHeroWeb.Gettext, "en")
      :ok
    end

    test "returns 'No children yet' for an empty list" do
      assert ChildPresenter.children_summary([]) == "No children yet"
    end

    test "returns 'Name (age)' for a single child" do
      child = build_child(%{first_name: "Emma", last_name: "Schmidt", date_of_birth: birthday_in_past(7)})
      assert ChildPresenter.children_summary([child]) == "Emma Schmidt (7)"
    end

    test "returns comma-separated summaries for multiple children" do
      child1 = build_child(%{first_name: "Emma", last_name: "Schmidt", date_of_birth: birthday_in_past(7)})
      child2 = build_child(%{first_name: "Luca", last_name: "Bauer", date_of_birth: birthday_in_past(5)})

      result = ChildPresenter.children_summary([child1, child2])
      assert result == "Emma Schmidt (7), Luca Bauer (5)"
    end
  end
end
