defmodule KlassHero.Enrollment.ParticipantPolicyFormTest do
  use ExUnit.Case, async: true

  alias KlassHero.Enrollment.ParticipantPolicyForm

  describe "changeset/2 — valid inputs" do
    test "accepts all fields with valid values" do
      attrs = %{
        eligibility_at: "program_start",
        min_age_months: 48,
        max_age_months: 144,
        allowed_genders: ["male", "female"],
        min_grade: 1,
        max_grade: 6
      }

      changeset = ParticipantPolicyForm.changeset(attrs)
      assert changeset.valid?
    end

    test "accepts empty attrs (all fields are optional, defaults apply)" do
      changeset = ParticipantPolicyForm.changeset(%{})
      assert changeset.valid?
    end

    test "accepts registration eligibility_at (default value)" do
      changeset = ParticipantPolicyForm.changeset(%{eligibility_at: "registration"})
      assert changeset.valid?
    end

    test "accepts program_start eligibility_at" do
      changeset = ParticipantPolicyForm.changeset(%{eligibility_at: "program_start"})
      assert changeset.valid?
    end

    test "accepts zero min_age_months (boundary)" do
      changeset = ParticipantPolicyForm.changeset(%{min_age_months: 0})
      assert changeset.valid?
    end

    test "accepts zero max_age_months (boundary)" do
      changeset = ParticipantPolicyForm.changeset(%{max_age_months: 0})
      assert changeset.valid?
    end

    test "accepts grade 1 for min_grade (lower boundary)" do
      changeset = ParticipantPolicyForm.changeset(%{min_grade: 1})
      assert changeset.valid?
    end

    test "accepts grade 13 for max_grade (upper boundary)" do
      changeset = ParticipantPolicyForm.changeset(%{max_grade: 13})
      assert changeset.valid?
    end

    test "accepts all valid genders" do
      changeset =
        ParticipantPolicyForm.changeset(%{
          allowed_genders: ["male", "female", "diverse", "not_specified"]
        })

      assert changeset.valid?
    end

    test "accepts empty allowed_genders list" do
      changeset = ParticipantPolicyForm.changeset(%{allowed_genders: []})
      assert changeset.valid?
    end

    test "accepts equal min_age_months and max_age_months (boundary equality)" do
      changeset =
        ParticipantPolicyForm.changeset(%{min_age_months: 60, max_age_months: 60})

      assert changeset.valid?
    end

    test "accepts equal min_grade and max_grade (boundary equality)" do
      changeset = ParticipantPolicyForm.changeset(%{min_grade: 5, max_grade: 5})
      assert changeset.valid?
    end

    test "accepts only min_age_months without max (no cross-field error)" do
      changeset = ParticipantPolicyForm.changeset(%{min_age_months: 48})
      assert changeset.valid?
    end

    test "accepts only max_age_months without min (no cross-field error)" do
      changeset = ParticipantPolicyForm.changeset(%{max_age_months: 144})
      assert changeset.valid?
    end

    test "accepts only min_grade without max" do
      changeset = ParticipantPolicyForm.changeset(%{min_grade: 3})
      assert changeset.valid?
    end

    test "accepts only max_grade without min" do
      changeset = ParticipantPolicyForm.changeset(%{max_grade: 8})
      assert changeset.valid?
    end
  end

  describe "changeset/2 — invalid eligibility_at" do
    test "rejects unknown eligibility_at value" do
      changeset = ParticipantPolicyForm.changeset(%{eligibility_at: "on_payment"})
      refute changeset.valid?
      assert {_, opts} = changeset.errors[:eligibility_at]
      assert opts[:validation] == :inclusion
    end
  end

  describe "changeset/2 — invalid age bounds" do
    test "rejects negative min_age_months" do
      changeset = ParticipantPolicyForm.changeset(%{min_age_months: -1})
      refute changeset.valid?
      assert {_, opts} = changeset.errors[:min_age_months]
      assert opts[:validation] == :number
    end

    test "rejects negative max_age_months" do
      changeset = ParticipantPolicyForm.changeset(%{max_age_months: -1})
      refute changeset.valid?
      assert {_, opts} = changeset.errors[:max_age_months]
      assert opts[:validation] == :number
    end
  end

  describe "changeset/2 — invalid grade bounds" do
    test "rejects min_grade of 0 (below minimum of 1)" do
      changeset = ParticipantPolicyForm.changeset(%{min_grade: 0})
      refute changeset.valid?
      assert {_, opts} = changeset.errors[:min_grade]
      assert opts[:validation] == :number
    end

    test "rejects max_grade of 14 (above maximum of 13)" do
      changeset = ParticipantPolicyForm.changeset(%{max_grade: 14})
      refute changeset.valid?
      assert {_, opts} = changeset.errors[:max_grade]
      assert opts[:validation] == :number
    end

    test "rejects negative min_grade" do
      changeset = ParticipantPolicyForm.changeset(%{min_grade: -1})
      refute changeset.valid?
      assert changeset.errors[:min_grade]
    end
  end

  describe "changeset/2 — invalid allowed_genders" do
    test "rejects unknown gender value" do
      changeset = ParticipantPolicyForm.changeset(%{allowed_genders: ["unknown"]})
      refute changeset.valid?
      assert {msg, []} = changeset.errors[:allowed_genders]
      assert String.contains?(msg, "invalid values")
      assert String.contains?(msg, "unknown")
    end

    test "rejects list with mixed valid and invalid genders" do
      changeset =
        ParticipantPolicyForm.changeset(%{allowed_genders: ["male", "robot", "female"]})

      refute changeset.valid?
      assert {msg, []} = changeset.errors[:allowed_genders]
      assert String.contains?(msg, "robot")
    end

    test "reports all invalid values in error message" do
      changeset =
        ParticipantPolicyForm.changeset(%{allowed_genders: ["bad1", "bad2"]})

      refute changeset.valid?
      assert {msg, []} = changeset.errors[:allowed_genders]
      assert String.contains?(msg, "bad1")
      assert String.contains?(msg, "bad2")
    end
  end

  describe "changeset/2 — cross-field age range validation" do
    test "rejects min_age_months > max_age_months" do
      changeset =
        ParticipantPolicyForm.changeset(%{min_age_months: 120, max_age_months: 48})

      refute changeset.valid?
      assert {msg, []} = changeset.errors[:min_age_months]
      assert String.contains?(msg, "maximum age")
    end

    test "accepts min_age_months < max_age_months" do
      changeset =
        ParticipantPolicyForm.changeset(%{min_age_months: 48, max_age_months: 120})

      assert changeset.valid?
    end
  end

  describe "changeset/2 — cross-field grade range validation" do
    test "rejects min_grade > max_grade" do
      changeset = ParticipantPolicyForm.changeset(%{min_grade: 8, max_grade: 3})
      refute changeset.valid?
      assert {msg, []} = changeset.errors[:min_grade]
      assert String.contains?(msg, "maximum grade")
    end

    test "accepts min_grade < max_grade" do
      changeset = ParticipantPolicyForm.changeset(%{min_grade: 3, max_grade: 8})
      assert changeset.valid?
    end
  end

  describe "changeset/2 — default values" do
    test "eligibility_at defaults to registration" do
      changeset = ParticipantPolicyForm.changeset(%{})
      assert Ecto.Changeset.get_field(changeset, :eligibility_at) == "registration"
    end

    test "allowed_genders defaults to empty list" do
      changeset = ParticipantPolicyForm.changeset(%{})
      assert Ecto.Changeset.get_field(changeset, :allowed_genders) == []
    end
  end

  describe "changeset/2 — update form struct" do
    test "accepts an existing form struct and applies changes" do
      existing = %ParticipantPolicyForm{eligibility_at: "registration", min_age_months: 24}

      changeset =
        ParticipantPolicyForm.changeset(existing, %{
          eligibility_at: "program_start",
          min_age_months: 48
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :eligibility_at) == "program_start"
      assert Ecto.Changeset.get_field(changeset, :min_age_months) == 48
    end
  end
end
