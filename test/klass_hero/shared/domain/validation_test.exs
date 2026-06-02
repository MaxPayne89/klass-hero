defmodule KlassHero.Shared.Domain.ValidationTest do
  use ExUnit.Case, async: true

  alias KlassHero.Shared.Domain.Validation

  describe "validate_required_string/3" do
    test "returns errors unchanged when value is a non-empty string" do
      assert Validation.validate_required_string([], :name, "Alice") == []
    end

    test "preserves existing errors when value is valid" do
      prior = ["other error"]
      assert Validation.validate_required_string(prior, :name, "Bob") == ["other error"]
    end

    test "prepends error when value is an empty string" do
      errors = Validation.validate_required_string([], :name, "")
      assert errors == ["name cannot be empty"]
    end

    test "prepends error when value is whitespace-only" do
      errors = Validation.validate_required_string([], :name, "   ")
      assert errors == ["name cannot be empty"]
    end

    test "prepends error when value is a tab/newline string" do
      errors = Validation.validate_required_string([], :email, "\t\n")
      assert errors == ["email cannot be empty"]
    end

    test "prepends error when value is nil" do
      errors = Validation.validate_required_string([], :name, nil)
      assert errors == ["name must be a string"]
    end

    test "prepends error when value is an integer" do
      errors = Validation.validate_required_string([], :age, 42)
      assert errors == ["age must be a string"]
    end

    test "prepends error when value is a list" do
      errors = Validation.validate_required_string([], :tags, [])
      assert errors == ["tags must be a string"]
    end

    test "accumulates errors from multiple invalid fields" do
      errors =
        []
        |> Validation.validate_required_string(:name, nil)
        |> Validation.validate_required_string(:email, "")

      assert "name must be a string" in errors
      assert "email cannot be empty" in errors
    end

    test "uses field name in the error message (atom field)" do
      [error] = Validation.validate_required_string([], :subject, "")
      assert String.contains?(error, "subject")
    end

    test "uses field name in the error message (string field)" do
      [error] = Validation.validate_required_string([], "subject", "")
      assert String.contains?(error, "subject")
    end
  end
end
