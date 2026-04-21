defmodule KlassHero.Enrollment.Domain.Services.InviteFieldValidationsTest do
  use ExUnit.Case, async: true

  alias KlassHero.Enrollment.Domain.Services.InviteFieldValidations

  import Ecto.Changeset

  # Minimal embedded schema to test InviteFieldValidations in isolation,
  # without coupling to any specific caller schema.
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

    def changeset(attrs) do
      %__MODULE__{}
      |> cast(attrs, @all_fields)
      |> InviteFieldValidations.apply()
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
    child_date_of_birth: Date.add(Date.utc_today(), -365),
    guardian_email: "parent@example.com"
  }

  describe "apply/1" do
    test "returns valid changeset for all valid inputs" do
      assert TestSchema.changeset(@valid_attrs).valid?
    end

    # child_first_name length: min 1, max 100
    test "rejects child_first_name shorter than 1 character" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :child_first_name, ""))
      assert errors_on(changeset)[:child_first_name]
    end

    test "rejects child_first_name longer than 100 characters" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :child_first_name, String.duplicate("a", 101)))
      assert errors_on(changeset)[:child_first_name]
    end

    test "accepts child_first_name at the 100-character limit" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :child_first_name, String.duplicate("a", 100)))
      refute errors_on(changeset)[:child_first_name]
    end

    # child_last_name length: min 1, max 100
    test "rejects child_last_name longer than 100 characters" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :child_last_name, String.duplicate("a", 101)))
      assert errors_on(changeset)[:child_last_name]
    end

    # guardian_email length: max 160; also format-validated
    test "rejects guardian_email longer than 160 characters" do
      long_email = String.duplicate("a", 155) <> "@b.com"
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :guardian_email, long_email))
      assert errors_on(changeset)[:guardian_email]
    end

    test "rejects guardian_email with invalid format" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :guardian_email, "not-an-email"))
      assert errors_on(changeset)[:guardian_email] == ["must be a valid email"]
    end

    # guardian2_email: conditional validation via maybe_validate_guardian2_email/1
    # nil and "" skip the format check; a non-empty value must match the regex
    test "accepts nil guardian2_email without format check" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :guardian2_email, nil))
      refute errors_on(changeset)[:guardian2_email]
    end

    test "accepts empty guardian2_email without format check" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :guardian2_email, ""))
      refute errors_on(changeset)[:guardian2_email]
    end

    test "accepts guardian2_email with valid email format" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :guardian2_email, "second@example.com"))
      refute errors_on(changeset)[:guardian2_email]
    end

    test "rejects non-empty guardian2_email with invalid format" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :guardian2_email, "nope"))
      assert errors_on(changeset)[:guardian2_email] == ["must be a valid email"]
    end

    # child_date_of_birth: must be a date strictly before today
    test "rejects child_date_of_birth set to today" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :child_date_of_birth, Date.utc_today()))
      assert errors_on(changeset)[:child_date_of_birth] == ["must be in the past"]
    end

    test "accepts child_date_of_birth set to yesterday" do
      yesterday = Date.add(Date.utc_today(), -1)
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :child_date_of_birth, yesterday))
      refute errors_on(changeset)[:child_date_of_birth]
    end

    # school_grade: valid range is 1..13
    test "rejects school_grade below 1" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :school_grade, 0))
      assert errors_on(changeset)[:school_grade]
    end

    test "rejects school_grade above 13" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :school_grade, 14))
      assert errors_on(changeset)[:school_grade]
    end

    test "accepts school_grade at lower bound 1" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :school_grade, 1))
      refute errors_on(changeset)[:school_grade]
    end

    test "accepts school_grade at upper bound 13" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :school_grade, 13))
      refute errors_on(changeset)[:school_grade]
    end

    # guardian2 optional name field length limits
    test "rejects guardian2_first_name longer than 100 characters" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :guardian2_first_name, String.duplicate("a", 101)))
      assert errors_on(changeset)[:guardian2_first_name]
    end

    test "rejects guardian2_last_name longer than 100 characters" do
      changeset = TestSchema.changeset(Map.put(@valid_attrs, :guardian2_last_name, String.duplicate("a", 101)))
      assert errors_on(changeset)[:guardian2_last_name]
    end
  end
end
