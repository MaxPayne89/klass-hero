defmodule KlassHero.Family.ChildTest do
  @moduledoc """
  Unit tests for the Child schema: changeset validation (the single validation
  gatekeeper) and the pure functional-core helpers.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Family.Child

  @valid_attrs %{
    first_name: "Emma",
    last_name: "Smith",
    date_of_birth: ~D[2015-06-15]
  }

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  describe "changeset/2 - valid input" do
    test "valid with only required fields" do
      assert Child.changeset(%Child{}, @valid_attrs).valid?
    end

    test "valid with all fields populated" do
      attrs =
        Map.merge(@valid_attrs, %{
          gender: "female",
          school_grade: 3,
          school_name: "Berlin International School",
          emergency_contact: "555-1234",
          support_needs: "Extra help with reading",
          allergies: "Peanuts"
        })

      assert Child.changeset(%Child{}, attrs).valid?
    end
  end

  describe "changeset/2 - required fields" do
    for field <- [:first_name, :last_name, :date_of_birth] do
      test "is invalid without #{field}" do
        changeset = Child.changeset(%Child{}, Map.delete(@valid_attrs, unquote(field)))

        refute changeset.valid?
        assert %{unquote(field) => ["can't be blank"]} = errors_on(changeset)
      end
    end

    test "treats a blank first_name as missing" do
      changeset = Child.changeset(%Child{}, %{@valid_attrs | first_name: ""})

      refute changeset.valid?
      assert %{first_name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "changeset/2 - date_of_birth" do
    test "is invalid when in the future" do
      future = Date.add(Date.utc_today(), 1)
      changeset = Child.changeset(%Child{}, %{@valid_attrs | date_of_birth: future})

      refute changeset.valid?
      assert %{date_of_birth: ["must be in the past"]} = errors_on(changeset)
    end

    test "is valid for today minus one day (boundary: one before today)" do
      yesterday = Date.add(Date.utc_today(), -1)
      assert Child.changeset(%Child{}, %{@valid_attrs | date_of_birth: yesterday}).valid?
    end
  end

  describe "changeset/2 - gender" do
    test "accepts every valid gender" do
      for gender <- Child.valid_genders() do
        assert Child.changeset(%Child{}, Map.put(@valid_attrs, :gender, gender)).valid?,
               "expected gender #{inspect(gender)} to be valid"
      end
    end

    test "rejects an unknown gender" do
      changeset = Child.changeset(%Child{}, Map.put(@valid_attrs, :gender, "other"))

      refute changeset.valid?
      assert %{gender: [_]} = errors_on(changeset)
    end
  end

  describe "changeset/2 - school_grade boundaries" do
    test "accepts grades 1 through 13" do
      for grade <- 1..13 do
        assert Child.changeset(%Child{}, Map.put(@valid_attrs, :school_grade, grade)).valid?,
               "expected grade #{grade} to be valid"
      end
    end

    test "rejects 0 (one below the boundary)" do
      refute Child.changeset(%Child{}, Map.put(@valid_attrs, :school_grade, 0)).valid?
    end

    test "rejects 14 (one above the boundary)" do
      refute Child.changeset(%Child{}, Map.put(@valid_attrs, :school_grade, 14)).valid?
    end
  end

  describe "full_name/1" do
    test "joins first and last name" do
      assert Child.full_name(%Child{first_name: "Emma", last_name: "Smith"}) == "Emma Smith"
    end
  end

  describe "anonymized_attrs/0" do
    test "blanks every PII field and clears date_of_birth" do
      attrs = Child.anonymized_attrs()

      assert attrs.first_name == "Anonymized"
      assert attrs.last_name == "Child"
      assert attrs.date_of_birth == nil
      assert attrs.emergency_contact == nil
      assert attrs.support_needs == nil
      assert attrs.allergies == nil
      assert attrs.school_name == nil
      assert attrs.school_grade == nil
    end
  end

  describe "age_in_months/2" do
    setup do
      %{child: %Child{date_of_birth: ~D[2015-06-15]}}
    end

    test "computes whole months on the same day-of-month", %{child: child} do
      assert Child.age_in_months(child, ~D[2017-12-15]) == 30
    end

    test "subtracts a month when the birthday hasn't been reached this month" do
      child = %Child{date_of_birth: ~D[2015-06-20]}
      assert Child.age_in_months(child, ~D[2016-06-10]) == 11
    end

    test "does not subtract on or after the birth day-of-month", %{child: child} do
      assert Child.age_in_months(child, ~D[2016-06-15]) == 12
      assert Child.age_in_months(child, ~D[2016-06-20]) == 12
    end

    test "is 0 when the reference date equals the date of birth", %{child: child} do
      assert Child.age_in_months(child, ~D[2015-06-15]) == 0
    end

    test "is 0 when the reference date precedes the date of birth", %{child: child} do
      assert Child.age_in_months(child, ~D[2015-01-01]) == 0
    end
  end
end
