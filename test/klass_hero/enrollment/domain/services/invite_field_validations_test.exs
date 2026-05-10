defmodule KlassHero.Enrollment.Domain.Services.InviteFieldValidationsTest do
  use ExUnit.Case, async: true

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

  describe "apply/1" do
    test "returns valid changeset for all valid inputs" do
      assert TestSchema.changeset(@valid_attrs).valid?
    end

    test "rejects field over its max length" do
      for {field, max} <- @length_max_cases do
        over = String.duplicate("a", max + 1)
        cs = TestSchema.changeset(Map.put(@valid_attrs, field, over))

        assert errors_on(cs)[field],
               "expected length error on #{field} at #{max + 1} chars, got: #{inspect(errors_on(cs))}"
      end
    end

    # At-limit boundaries that don't fit the over-limit table
    test "accepts child_first_name at the 100-character limit" do
      cs = TestSchema.changeset(Map.put(@valid_attrs, :child_first_name, String.duplicate("a", 100)))
      refute errors_on(cs)[:child_first_name]
    end

    test "accepts child_last_name at the 100-character limit" do
      cs = TestSchema.changeset(Map.put(@valid_attrs, :child_last_name, String.duplicate("a", 100)))
      refute errors_on(cs)[:child_last_name]
    end

    # Format validation is a distinct semantic from length
    test "rejects guardian_email with invalid format" do
      cs = TestSchema.changeset(Map.put(@valid_attrs, :guardian_email, "not-an-email"))
      assert errors_on(cs)[:guardian_email] == ["must be a valid email"]
    end

    # guardian2_email: conditional validation via maybe_validate_guardian2_email/1
    # nil and "" skip the format check; a non-empty value must match the regex
    test "accepts nil guardian2_email without format check" do
      cs = TestSchema.changeset(Map.put(@valid_attrs, :guardian2_email, nil))
      refute errors_on(cs)[:guardian2_email]
    end

    test "accepts empty guardian2_email without format check" do
      cs = TestSchema.changeset(Map.put(@valid_attrs, :guardian2_email, ""))
      refute errors_on(cs)[:guardian2_email]
    end

    test "accepts guardian2_email with valid email format" do
      cs = TestSchema.changeset(Map.put(@valid_attrs, :guardian2_email, "second@example.com"))
      refute errors_on(cs)[:guardian2_email]
    end

    test "rejects non-empty guardian2_email with invalid format" do
      cs = TestSchema.changeset(Map.put(@valid_attrs, :guardian2_email, "nope"))
      assert errors_on(cs)[:guardian2_email] == ["must be a valid email"]
    end

    # child_date_of_birth: must be strictly before the injected `today`
    test "rejects child_date_of_birth set to today" do
      today = ~D[2026-05-10]
      cs = TestSchema.changeset(Map.put(@valid_attrs, :child_date_of_birth, today), today)
      assert errors_on(cs)[:child_date_of_birth] == ["must be in the past"]
    end

    test "accepts child_date_of_birth set to yesterday" do
      today = ~D[2026-05-10]
      yesterday = Date.add(today, -1)
      cs = TestSchema.changeset(Map.put(@valid_attrs, :child_date_of_birth, yesterday), today)
      refute errors_on(cs)[:child_date_of_birth]
    end

    # school_grade: valid range is 1..13
    test "rejects school_grade below 1" do
      cs = TestSchema.changeset(Map.put(@valid_attrs, :school_grade, 0))
      assert errors_on(cs)[:school_grade]
    end

    test "rejects school_grade above 13" do
      cs = TestSchema.changeset(Map.put(@valid_attrs, :school_grade, 14))
      assert errors_on(cs)[:school_grade]
    end

    test "accepts school_grade at lower bound 1" do
      cs = TestSchema.changeset(Map.put(@valid_attrs, :school_grade, 1))
      refute errors_on(cs)[:school_grade]
    end

    test "accepts school_grade at upper bound 13" do
      cs = TestSchema.changeset(Map.put(@valid_attrs, :school_grade, 13))
      refute errors_on(cs)[:school_grade]
    end
  end
end
