defmodule KlassHero.Enrollment.Domain.Services.InviteFieldValidationsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Enrollment.Domain.Services.InviteFieldValidations

  # Minimal embedded schema to test InviteFieldValidations in isolation,
  # without coupling to any specific caller schema. Keep field list in
  # sync with InviteFieldValidations source if new fields are added.
  defmodule TestSchema do
    @moduledoc false
    use Ecto.Schema

    import Ecto.Changeset

    embedded_schema do
      field :child_first_name, :string
      field :child_last_name, :string
      field :child_date_of_birth, :date
      field :guardian_email, :string
      field :guardian_first_name, :string
      field :guardian_last_name, :string
      field :guardian2_email, :string
      field :guardian2_first_name, :string
      field :guardian2_last_name, :string
      field :school_grade, :integer
      field :school_name, :string
    end

    @all_fields ~w(child_first_name child_last_name child_date_of_birth guardian_email
      guardian_first_name guardian_last_name guardian2_email guardian2_first_name
      guardian2_last_name school_grade school_name)a

    def changeset(attrs, today \\ Date.utc_today()) do
      %__MODULE__{}
      |> cast(attrs, @all_fields)
      |> InviteFieldValidations.apply(today)
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @valid_attrs %{
    child_first_name: "Emma",
    child_last_name: "Schmidt",
    child_date_of_birth: ~D[2025-05-10],
    guardian_email: "parent@example.com"
  }

  describe "apply/1" do
    test "returns valid changeset for all valid inputs" do
      assert TestSchema.changeset(@valid_attrs).valid?
    end
  end

  @length_max_cases [
    {:child_first_name, 100},
    {:child_last_name, 100},
    {:guardian_first_name, 100},
    {:guardian_last_name, 100},
    {:guardian_email, 160},
    {:guardian2_email, 160},
    {:guardian2_first_name, 100},
    {:guardian2_last_name, 100},
    {:school_name, 255}
  ]

  # guardian_email/guardian2_email also carry a format validation, so the
  # filler must stay a valid email shape or a boundary test would trip the
  # format check instead of the length check it's meant to isolate.
  defp filler(field, length) when field in [:guardian_email, :guardian2_email] do
    domain = "@example.com"
    String.duplicate("a", length - String.length(domain)) <> domain
  end

  defp filler(_field, length), do: String.duplicate("a", length)

  describe "field length limits" do
    test "rejects a field one character over its max length, accepts it at the max" do
      for {field, max} <- @length_max_cases do
        over_cs = TestSchema.changeset(Map.put(@valid_attrs, field, filler(field, max + 1)))
        at_cs = TestSchema.changeset(Map.put(@valid_attrs, field, filler(field, max)))

        assert errors_on(over_cs)[field],
               "expected length error on #{field} at #{max + 1} chars, got: #{inspect(errors_on(over_cs))}"

        refute errors_on(at_cs)[field],
               "expected no length error on #{field} at #{max} chars, got: #{inspect(errors_on(at_cs))}"
      end
    end
  end

  # Only guardian 1 becomes an `Accounts.User`, whose name is `min: 2`. Guardian 2 and the
  # child have no such floor, so the minimum is deliberately asymmetric.
  @length_min_cases [
    {:guardian_first_name, 2},
    {:guardian_last_name, 2}
  ]

  describe "guardian name minimum length" do
    test "rejects a name one character under its min, accepts it at the min" do
      for {field, min} <- @length_min_cases do
        under_cs = TestSchema.changeset(Map.put(@valid_attrs, field, filler(field, min - 1)))
        at_cs = TestSchema.changeset(Map.put(@valid_attrs, field, filler(field, min)))

        assert errors_on(under_cs)[field],
               "expected length error on #{field} at #{min - 1} chars, got: #{inspect(errors_on(under_cs))}"

        refute errors_on(at_cs)[field],
               "expected no length error on #{field} at #{min} chars, got: #{inspect(errors_on(at_cs))}"
      end
    end

    # A guardian known only by email is legitimate — `ClaimInvite` names them "Guardian".
    # The minimum must not turn that into an import rejection.
    test "leaves absent guardian names alone" do
      cs =
        TestSchema.changeset(Map.merge(@valid_attrs, %{guardian_first_name: nil, guardian_last_name: nil}))

      refute errors_on(cs)[:guardian_first_name]
      refute errors_on(cs)[:guardian_last_name]
    end
  end

  describe "guardian_email format" do
    # Format validation is a distinct semantic from length
    test "rejects an invalid format" do
      cs = TestSchema.changeset(Map.put(@valid_attrs, :guardian_email, "not-an-email"))
      assert errors_on(cs)[:guardian_email] == ["must be a valid email"]
    end
  end

  # guardian2_email: conditional validation via maybe_validate_guardian2_email/1.
  # nil and "" skip the format check; a non-empty value must match the regex.
  @guardian2_email_cases [
    {nil, nil, "nil skips the format check"},
    {"", nil, "empty string skips the format check"},
    {"second@example.com", nil, "valid format has no error"},
    {"nope", ["must be a valid email"], "invalid format is rejected"}
  ]

  describe "guardian2_email conditional format check" do
    test "format is only enforced on a non-blank value" do
      for {value, expected_errors, label} <- @guardian2_email_cases do
        cs = TestSchema.changeset(Map.put(@valid_attrs, :guardian2_email, value))
        assert errors_on(cs)[:guardian2_email] == expected_errors, label
      end
    end
  end

  # child_date_of_birth: must be strictly before the injected `today`
  describe "child_date_of_birth" do
    test "rejects a date set to today" do
      today = ~D[2026-05-10]
      cs = TestSchema.changeset(Map.put(@valid_attrs, :child_date_of_birth, today), today)
      assert errors_on(cs)[:child_date_of_birth] == ["must be in the past"]
    end

    test "accepts a date set to yesterday" do
      today = ~D[2026-05-10]
      yesterday = Date.add(today, -1)
      cs = TestSchema.changeset(Map.put(@valid_attrs, :child_date_of_birth, yesterday), today)
      refute errors_on(cs)[:child_date_of_birth]
    end
  end

  @school_grade_cases [
    {0, true, "below the 1..13 range"},
    {14, true, "above the 1..13 range"},
    {1, false, "at the lower bound"},
    {13, false, "at the upper bound"}
  ]

  describe "school_grade range" do
    test "must be in 1..13" do
      for {grade, error_expected?, label} <- @school_grade_cases do
        cs = TestSchema.changeset(Map.put(@valid_attrs, :school_grade, grade))

        if error_expected? do
          assert errors_on(cs)[:school_grade], label
        else
          refute errors_on(cs)[:school_grade], label
        end
      end
    end

    property "errors iff the grade falls outside 1..13" do
      check all(grade <- integer(-50..50)) do
        cs = TestSchema.changeset(Map.put(@valid_attrs, :school_grade, grade))

        if grade in 1..13 do
          refute errors_on(cs)[:school_grade]
        else
          assert errors_on(cs)[:school_grade]
        end
      end
    end
  end
end
