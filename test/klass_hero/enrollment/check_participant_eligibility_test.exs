defmodule KlassHero.Enrollment.CheckParticipantEligibilityTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment

  describe "check_participant_eligibility/2" do
    test "returns eligible when no policy exists for program" do
      program = insert(:program_schema)
      child = insert(:child_schema, date_of_birth: ~D[2018-06-15], gender: "male")

      assert {:ok, :eligible} =
               Enrollment.check_participant_eligibility(program.id, child.id)
    end

    test "returns eligible when child meets all restrictions" do
      program = insert(:program_schema)

      child =
        insert(:child_schema,
          date_of_birth: ~D[2018-06-15],
          gender: "male",
          school_grade: 3
        )

      {:ok, _policy} =
        Enrollment.set_participant_policy(%{
          program_id: program.id,
          min_age_months: 60,
          max_age_months: 120,
          allowed_genders: ["male", "female"],
          min_grade: 1,
          max_grade: 6,
          eligibility_at: "registration"
        })

      assert {:ok, :eligible} =
               Enrollment.check_participant_eligibility(program.id, child.id)
    end

    test "returns ineligible when child is too young" do
      program = insert(:program_schema)

      # Born recently — very young child
      child =
        insert(:child_schema,
          date_of_birth: Date.add(Date.utc_today(), -30),
          gender: "male"
        )

      {:ok, _policy} =
        Enrollment.set_participant_policy(%{
          program_id: program.id,
          min_age_months: 60,
          eligibility_at: "registration"
        })

      assert {:error, :ineligible, reasons} =
               Enrollment.check_participant_eligibility(program.id, child.id)

      assert Enum.any?(reasons, &String.contains?(&1, "too young"))
    end

    test "returns ineligible when child is too old" do
      program = insert(:program_schema)

      # Born 20 years ago — well above max
      child =
        insert(:child_schema,
          date_of_birth: ~D[2005-01-01],
          gender: "female"
        )

      {:ok, _policy} =
        Enrollment.set_participant_policy(%{
          program_id: program.id,
          max_age_months: 120,
          eligibility_at: "registration"
        })

      assert {:error, :ineligible, reasons} =
               Enrollment.check_participant_eligibility(program.id, child.id)

      assert Enum.any?(reasons, &String.contains?(&1, "too old"))
    end

    test "returns ineligible when gender is not allowed" do
      program = insert(:program_schema)

      child =
        insert(:child_schema,
          date_of_birth: ~D[2018-06-15],
          gender: "male"
        )

      {:ok, _policy} =
        Enrollment.set_participant_policy(%{
          program_id: program.id,
          allowed_genders: ["female"],
          eligibility_at: "registration"
        })

      assert {:error, :ineligible, reasons} =
               Enrollment.check_participant_eligibility(program.id, child.id)

      assert Enum.any?(reasons, &String.contains?(&1, "gender not allowed"))
    end

    test "returns ineligible when grade is below minimum" do
      program = insert(:program_schema)

      child =
        insert(:child_schema,
          date_of_birth: ~D[2018-06-15],
          gender: "male",
          school_grade: 1
        )

      {:ok, _policy} =
        Enrollment.set_participant_policy(%{
          program_id: program.id,
          min_grade: 3,
          max_grade: 6,
          eligibility_at: "registration"
        })

      assert {:error, :ineligible, reasons} =
               Enrollment.check_participant_eligibility(program.id, child.id)

      assert Enum.any?(reasons, &String.contains?(&1, "grade too low"))
    end

    test "uses program start_date for age calculation when eligibility_at is program_start" do
      # Program starts in the future — child will be older by then
      future_start = Date.add(Date.utc_today(), 365)
      program = insert(:program_schema, start_date: future_start)

      # Child is currently 59 months old, but will be ~71 months at program start
      birth_date = Date.shift(Date.utc_today(), month: -59)

      child =
        insert(:child_schema,
          date_of_birth: birth_date,
          gender: "male"
        )

      {:ok, _policy} =
        Enrollment.set_participant_policy(%{
          program_id: program.id,
          min_age_months: 60,
          max_age_months: 120,
          eligibility_at: "program_start"
        })

      # At program start (1 year from now), the child will be ~71 months — eligible
      assert {:ok, :eligible} =
               Enrollment.check_participant_eligibility(program.id, child.id)
    end

    test "falls back to today when eligibility_at is program_start but start_date is nil" do
      program = insert(:program_schema, start_date: nil)

      # Born recently — very young child, too young for min_age 60
      child =
        insert(:child_schema,
          date_of_birth: Date.add(Date.utc_today(), -30),
          gender: "male"
        )

      {:ok, _policy} =
        Enrollment.set_participant_policy(%{
          program_id: program.id,
          min_age_months: 60,
          eligibility_at: "program_start"
        })

      # Falls back to today, child is ~1 month old — ineligible
      assert {:error, :ineligible, reasons} =
               Enrollment.check_participant_eligibility(program.id, child.id)

      assert Enum.any?(reasons, &String.contains?(&1, "too young"))
    end

    test "returns not_found when child does not exist" do
      program = insert(:program_schema)
      non_existent_child_id = Ecto.UUID.generate()

      {:ok, _policy} =
        Enrollment.set_participant_policy(%{
          program_id: program.id,
          min_age_months: 60,
          eligibility_at: "registration"
        })

      assert {:error, :not_found} =
               Enrollment.check_participant_eligibility(program.id, non_existent_child_id)
    end

    test "returns multiple failure reasons together" do
      program = insert(:program_schema)

      # Child who fails age AND gender AND grade checks
      child =
        insert(:child_schema,
          date_of_birth: Date.add(Date.utc_today(), -30),
          gender: "male",
          school_grade: 1
        )

      {:ok, _policy} =
        Enrollment.set_participant_policy(%{
          program_id: program.id,
          min_age_months: 60,
          max_age_months: 120,
          allowed_genders: ["female"],
          min_grade: 3,
          max_grade: 6,
          eligibility_at: "registration"
        })

      assert {:error, :ineligible, reasons} =
               Enrollment.check_participant_eligibility(program.id, child.id)

      assert length(reasons) >= 3
      assert Enum.any?(reasons, &String.contains?(&1, "too young"))
      assert Enum.any?(reasons, &String.contains?(&1, "gender not allowed"))
      assert Enum.any?(reasons, &String.contains?(&1, "grade too low"))
    end
  end
end
