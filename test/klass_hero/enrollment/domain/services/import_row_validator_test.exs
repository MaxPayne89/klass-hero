defmodule KlassHero.Enrollment.Domain.Services.ImportRowValidatorTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Enrollment.Domain.Services.ImportRowValidator

  # -- helpers ---------------------------------------------------------------

  @provider_id "provider-uuid-1"

  # Trigger: build_context in the use case now downcases keys for case-insensitive matching
  # Why: tests must mirror the actual runtime context shape
  # Outcome: keys are lowercase, matching what the validator receives
  @programs_by_title %{
    "ballsports & parkour" => "program-uuid-1",
    "organic arts" => "program-uuid-2"
  }

  defp context do
    %{
      provider_id: @provider_id,
      programs_by_title: @programs_by_title
    }
  end

  defp valid_row do
    %{
      child_first_name: "Avyan",
      child_last_name: "Srivastava",
      child_date_of_birth: ~D[2016-01-01],
      guardian_email: "vaibhavinuk@gmail.com",
      guardian_first_name: "Vaibhav",
      guardian_last_name: "Srivastava",
      guardian2_email: nil,
      guardian2_first_name: nil,
      guardian2_last_name: nil,
      school_grade: 3,
      school_name: nil,
      medical_conditions: nil,
      nut_allergy: false,
      consent_photo_marketing: false,
      consent_photo_social_media: false,
      program_name: "Ballsports & Parkour",
      instructor_name: nil,
      season: "Berlin International School 24/25: Semester 2"
    }
  end

  # -- happy path ------------------------------------------------------------

  describe "validate/2 happy path" do
    test "valid row returns enriched map with program_id, provider_id, and field passthrough" do
      assert {:ok, result} = ImportRowValidator.validate(valid_row(), context())

      assert result.program_id == "program-uuid-1"
      assert result.provider_id == @provider_id
      assert result.child_first_name == "Avyan"
      assert result.child_last_name == "Srivastava"
      assert result.child_date_of_birth == ~D[2016-01-01]
      assert result.guardian_email == "vaibhavinuk@gmail.com"
    end

    test "strips program_name, instructor_name, and season from output" do
      assert {:ok, result} = ImportRowValidator.validate(valid_row(), context())

      refute Map.has_key?(result, :program_name)
      refute Map.has_key?(result, :instructor_name)
      refute Map.has_key?(result, :season)
    end

    test "second guardian email passes through when present" do
      row = %{valid_row() | guardian2_email: "second@example.com"}

      assert {:ok, result} = ImportRowValidator.validate(row, context())
      assert result.guardian2_email == "second@example.com"
    end
  end

  # -- field-level errors ------------------------------------------------------

  # Every row exercises the same contract: one field is set to an invalid
  # value, every other field stays valid, and the expected {field, message}
  # error is among the accumulated errors.
  @error_cases [
    {:child_first_name, nil, {:child_first_name, "is required"}, "missing child_first_name"},
    {:child_first_name, "", {:child_first_name, "is required"}, "empty child_first_name"},
    {:child_last_name, nil, {:child_last_name, "is required"}, "missing child_last_name"},
    {:child_date_of_birth, nil, {:child_date_of_birth, "is required"}, "missing child_date_of_birth"},
    {:guardian_email, nil, {:guardian_email, "is required"}, "missing guardian_email"},
    {:program_name, nil, {:program_name, "is required"}, "missing program_name"},
    {:guardian_email, "not-an-email", {:guardian_email, "must be a valid email"}, "malformed guardian_email"},
    {:guardian_email, "has space@example.com", {:guardian_email, "must be a valid email"},
     "guardian_email with a space"},
    {:guardian2_email, "bad-email", {:guardian2_email, "must be a valid email"}, "malformed guardian2_email"},
    {:program_name, "Nonexistent Program", {:program_name, "program not found"}, "unknown program"},
    {:school_grade, 0, {:school_grade, "must be between 1 and 13"}, "grade below range"},
    {:school_grade, 14, {:school_grade, "must be between 1 and 13"}, "grade above range"}
  ]

  describe "field-level validation errors" do
    test "each known invalid value produces its expected error" do
      for {field, invalid_value, expected_error, label} <- @error_cases do
        row = Map.put(valid_row(), field, invalid_value)

        assert {:error, errors} = ImportRowValidator.validate(row, context())

        assert expected_error in errors,
               "#{label}: expected #{inspect(expected_error)} in #{inspect(errors)}"
      end
    end

    # child_date_of_birth is relative to Date.utc_today/0, so it must be
    # computed at test-run time, not baked into a compile-time module attribute.
    test "a date of birth today or in the future produces 'must be in the past'" do
      for dob <- [Date.utc_today(), Date.add(Date.utc_today(), 1)] do
        row = Map.put(valid_row(), :child_date_of_birth, dob)

        assert {:error, errors} = ImportRowValidator.validate(row, context())
        assert {:child_date_of_birth, "must be in the past"} in errors
      end
    end
  end

  # -- known-valid boundaries and optional fields -----------------------------

  @valid_cases [
    {:guardian2_email, nil, "nil guardian2_email is optional"},
    {:school_grade, nil, "nil school_grade is optional"},
    {:school_grade, 1, "grade 1 is the lower boundary"},
    {:school_grade, 13, "grade 13 is the upper boundary"}
  ]

  describe "known-valid boundary and optional values" do
    test "each is accepted and passed through unchanged" do
      for {field, value, label} <- @valid_cases do
        row = Map.put(valid_row(), field, value)

        assert {:ok, result} = ImportRowValidator.validate(row, context()), label
        assert Map.get(result, field) == value, label
      end
    end
  end

  # -- case-insensitive program matching --------------------------------------

  @case_insensitive_program_cases [
    {"ballsports & parkour", "program-uuid-1", "lowercase"},
    {"BALLSPORTS & PARKOUR", "program-uuid-1", "UPPERCASE"},
    {"Organic arts", "program-uuid-2", "MiXeD case"}
  ]

  describe "case-insensitive program matching" do
    test "program name resolves to its program_id regardless of case" do
      for {program_name, expected_program_id, label} <- @case_insensitive_program_cases do
        row = %{valid_row() | program_name: program_name}

        assert {:ok, result} = ImportRowValidator.validate(row, context())
        assert result.program_id == expected_program_id, label
      end
    end
  end

  # -- error accumulation ------------------------------------------------------

  describe "multiple errors accumulated" do
    test "returns all errors for a row with multiple problems" do
      row = %{
        valid_row()
        | child_first_name: nil,
          guardian_email: "bad",
          program_name: "Nonexistent",
          school_grade: 0
      }

      assert {:error, errors} = ImportRowValidator.validate(row, context())

      assert {:child_first_name, "is required"} in errors
      assert {:guardian_email, "must be a valid email"} in errors
      assert {:program_name, "program not found"} in errors
      assert {:school_grade, "must be between 1 and 13"} in errors

      # Verify at least 4 errors accumulated
      assert length(errors) >= 4
    end
  end

  # -- properties --------------------------------------------------------------

  describe "properties" do
    property "any row satisfying every validation rule is accepted, with program_id/provider_id injected and program_name/instructor_name/season stripped" do
      check all(
              program_name <- member_of(["Ballsports & Parkour", "BALLSPORTS & PARKOUR", "organic arts"]),
              grade <- one_of([constant(nil), integer(1..13)]),
              guardian2_local <- one_of([constant(nil), string(:alphanumeric, min_length: 1, max_length: 10)]),
              days_in_past <- integer(1..3650)
            ) do
        guardian2_email = guardian2_local && "#{guardian2_local}@example.com"

        row = %{
          valid_row()
          | program_name: program_name,
            school_grade: grade,
            guardian2_email: guardian2_email,
            child_date_of_birth: Date.add(Date.utc_today(), -days_in_past)
        }

        assert {:ok, result} = ImportRowValidator.validate(row, context())

        assert result.provider_id == @provider_id
        assert result.program_id in Map.values(@programs_by_title)
        refute Map.has_key?(result, :program_name)
        refute Map.has_key?(result, :instructor_name)
        refute Map.has_key?(result, :season)
      end
    end
  end
end
