defmodule KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpersTest do
  use ExUnit.Case, async: true

  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers

  describe "unique_constraint_violation?/2" do
    test "returns true when unique constraint violation exists for specified field" do
      errors = [{:identity_id, {"has already been taken", [constraint: :unique]}}]

      assert EctoErrorHelpers.unique_constraint_violation?(errors, :identity_id)
    end

    test "returns true when unique constraint violation exists among multiple errors" do
      errors = [
        {:email, {"is invalid", []}},
        {:identity_id, {"has already been taken", [constraint: :unique]}},
        {:name, {"can't be blank", []}}
      ]

      assert EctoErrorHelpers.unique_constraint_violation?(errors, :identity_id)
    end

    test "returns false when no constraint violation exists for field" do
      errors = [{:identity_id, {"is invalid", []}}]

      refute EctoErrorHelpers.unique_constraint_violation?(errors, :identity_id)
    end

    test "returns false when constraint violation is for different field" do
      errors = [{:email, {"has already been taken", [constraint: :unique]}}]

      refute EctoErrorHelpers.unique_constraint_violation?(errors, :identity_id)
    end

    test "returns false when constraint type is different" do
      errors = [{:identity_id, {"does not exist", [constraint: :foreign]}}]

      refute EctoErrorHelpers.unique_constraint_violation?(errors, :identity_id)
    end

    test "returns false for empty error list" do
      errors = []

      refute EctoErrorHelpers.unique_constraint_violation?(errors, :identity_id)
    end

    test "handles multiple constraint violations correctly" do
      errors = [
        {:email, {"has already been taken", [constraint: :unique]}},
        {:identity_id, {"has already been taken", [constraint: :unique]}}
      ]

      assert EctoErrorHelpers.unique_constraint_violation?(errors, :email)
      assert EctoErrorHelpers.unique_constraint_violation?(errors, :identity_id)
    end
  end

  describe "any_unique_constraint_violation?/1" do
    test "returns true when a unique constraint violation exists" do
      errors = [{:email, {"has already been taken", [constraint: :unique]}}]

      assert EctoErrorHelpers.any_unique_constraint_violation?(errors)
    end

    test "returns true when unique constraint exists among multiple errors" do
      errors = [
        {:name, {"can't be blank", []}},
        {:email, {"has already been taken", [constraint: :unique]}},
        {:age, {"must be a number", []}}
      ]

      assert EctoErrorHelpers.any_unique_constraint_violation?(errors)
    end

    test "returns false when no constraint violations exist" do
      errors = [{:email, {"is invalid", []}}]

      refute EctoErrorHelpers.any_unique_constraint_violation?(errors)
    end

    test "returns false when constraint type is different" do
      errors = [{:user_id, {"does not exist", [constraint: :foreign]}}]

      refute EctoErrorHelpers.any_unique_constraint_violation?(errors)
    end

    test "returns false for empty error list" do
      refute EctoErrorHelpers.any_unique_constraint_violation?([])
    end
  end

  describe "foreign_key_violation?/2" do
    test "returns true when foreign key constraint violation exists for specified field" do
      errors = [{:user_id, {"does not exist", [constraint: :foreign]}}]

      assert EctoErrorHelpers.foreign_key_violation?(errors, :user_id)
    end

    test "returns true when foreign key violation exists among multiple errors" do
      errors = [
        {:email, {"is invalid", []}},
        {:user_id, {"does not exist", [constraint: :foreign]}},
        {:name, {"can't be blank", []}}
      ]

      assert EctoErrorHelpers.foreign_key_violation?(errors, :user_id)
    end

    test "returns false when no constraint violation exists for field" do
      errors = [{:user_id, {"is invalid", []}}]

      refute EctoErrorHelpers.foreign_key_violation?(errors, :user_id)
    end

    test "returns false when constraint violation is for different field" do
      errors = [{:organization_id, {"does not exist", [constraint: :foreign]}}]

      refute EctoErrorHelpers.foreign_key_violation?(errors, :user_id)
    end

    test "returns false when constraint type is different" do
      errors = [{:user_id, {"has already been taken", [constraint: :unique]}}]

      refute EctoErrorHelpers.foreign_key_violation?(errors, :user_id)
    end

    test "returns false for empty error list" do
      errors = []

      refute EctoErrorHelpers.foreign_key_violation?(errors, :user_id)
    end
  end

  describe "constraint_violation?/3" do
    test "detects unique constraint violations" do
      errors = [{:email, {"has already been taken", [constraint: :unique]}}]

      assert EctoErrorHelpers.constraint_violation?(errors, :email, :unique)
    end

    test "detects foreign key constraint violations" do
      errors = [{:user_id, {"does not exist", [constraint: :foreign]}}]

      assert EctoErrorHelpers.constraint_violation?(errors, :user_id, :foreign)
    end

    test "detects check constraint violations" do
      errors = [{:age, {"must be greater than 0", [constraint: :check]}}]

      assert EctoErrorHelpers.constraint_violation?(errors, :age, :check)
    end

    test "returns false when field matches but constraint type differs" do
      errors = [{:email, {"has already been taken", [constraint: :unique]}}]

      refute EctoErrorHelpers.constraint_violation?(errors, :email, :foreign)
    end

    test "returns false when constraint type matches but field differs" do
      errors = [{:email, {"has already been taken", [constraint: :unique]}}]

      refute EctoErrorHelpers.constraint_violation?(errors, :username, :unique)
    end

    test "returns false when error has no constraint option" do
      errors = [{:email, {"is invalid", []}}]

      refute EctoErrorHelpers.constraint_violation?(errors, :email, :unique)
    end

    test "returns false for empty error list" do
      errors = []

      refute EctoErrorHelpers.constraint_violation?(errors, :email, :unique)
    end

    test "finds constraint violation among multiple errors" do
      errors = [
        {:name, {"can't be blank", []}},
        {:email, {"is invalid", []}},
        {:identity_id, {"has already been taken", [constraint: :unique]}},
        {:age, {"must be a number", []}}
      ]

      assert EctoErrorHelpers.constraint_violation?(errors, :identity_id, :unique)
      refute EctoErrorHelpers.constraint_violation?(errors, :name, :unique)
      refute EctoErrorHelpers.constraint_violation?(errors, :email, :unique)
    end
  end

  # `unsafe_validate_unique` and `unique_constraint` reject the same duplicate with
  # differently-tagged errors depending on which race window the competing row lands in.
  # Recovery code has to treat them alike, so both tags must be recognised — and nothing else.
  @conflict_cases [
    {"database constraint", [{:email, {"has already been taken", [constraint: :unique]}}], true},
    {"pre-flight check", [{:email, {"has already been taken", [validation: :unsafe_unique]}}], true},
    {"conflict alongside other errors",
     [
       {:name, {"should be at least %{count} character(s)", [count: 2, validation: :length]}},
       {:email, {"has already been taken", [validation: :unsafe_unique]}}
     ], true},
    {"unrelated validation on the same field", [{:email, {"is invalid", [validation: :format]}}], false},
    {"conflict on a different field", [{:identity_id, {"has already been taken", [constraint: :unique]}}], false},
    {"foreign-key rather than unique", [{:email, {"does not exist", [constraint: :foreign]}}], false},
    {"no errors at all", [], false}
  ]

  describe "unique_conflict?/2" do
    test "recognises a uniqueness conflict from either mechanism, and nothing else" do
      for {label, errors, expected} <- @conflict_cases do
        assert EctoErrorHelpers.unique_conflict?(errors, :email) == expected,
               "#{label}: expected unique_conflict?(#{inspect(errors)}, :email) to be #{expected}"
      end
    end
  end
end
