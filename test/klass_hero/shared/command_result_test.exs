defmodule KlassHero.Shared.CommandResultTest do
  use ExUnit.Case, async: true

  alias KlassHero.Shared.CommandResult

  describe "wrap_validation_errors/1" do
    test "wraps {:error, list} into {:error, {:validation_error, errors}}" do
      errors = ["name cannot be empty", "age must be a number"]

      assert CommandResult.wrap_validation_errors({:error, errors}) ==
               {:error, {:validation_error, errors}}
    end

    test "wraps empty error list" do
      assert CommandResult.wrap_validation_errors({:error, []}) ==
               {:error, {:validation_error, []}}
    end

    test "passes {:ok, value} through unchanged" do
      assert CommandResult.wrap_validation_errors({:ok, :some_entity}) == {:ok, :some_entity}
    end

    test "passes {:error, atom} through unchanged" do
      assert CommandResult.wrap_validation_errors({:error, :not_found}) == {:error, :not_found}
    end

    test "passes {:error, changeset} through unchanged when errors field is a map" do
      # A map-valued error is not a list — passthrough
      assert CommandResult.wrap_validation_errors({:error, %{field: "bad"}}) ==
               {:error, %{field: "bad"}}
    end

    test "passes nil through unchanged" do
      assert CommandResult.wrap_validation_errors(nil) == nil
    end

    test "passes bare :ok through unchanged" do
      assert CommandResult.wrap_validation_errors(:ok) == :ok
    end
  end
end
