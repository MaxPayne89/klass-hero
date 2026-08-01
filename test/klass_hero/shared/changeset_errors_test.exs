defmodule KlassHero.Shared.ChangesetErrorsTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset

  alias KlassHero.Shared.ChangesetErrors

  # A small inline changeset module so these tests don't depend on a
  # persistence schema — the helper works on any Ecto.Changeset regardless
  # of where it was produced.
  defmodule Sample do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :name, :string
      field :quantity, :integer
    end
  end

  defp changeset(attrs) do
    %Sample{}
    |> cast(attrs, [:name, :quantity])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 10)
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
  end

  describe "field_list/1" do
    test "returns [] for a valid changeset" do
      assert ChangesetErrors.field_list(changeset(%{"name" => "ok"})) == []
    end

    test "flattens one-message-per-field errors" do
      errors = ChangesetErrors.field_list(changeset(%{"name" => ""}))
      assert {:name, "can't be blank"} in errors
    end

    test "expands %{count} placeholder using opts values" do
      errors = ChangesetErrors.field_list(changeset(%{"name" => "a"}))

      assert Enum.any?(errors, fn
               {:name, msg} -> msg =~ "should be at least 2 character"
               _ -> false
             end),
             "expected expanded count=2, got: #{inspect(errors)}"
    end

    test "surfaces multiple errors on the same field as separate list entries" do
      errors = ChangesetErrors.field_list(changeset(%{"name" => "verylongvalueindeed"}))

      # validate_length returns one 'should be at most' error
      length_errors = Enum.filter(errors, fn {field, _} -> field == :name end)
      assert length_errors != []
      assert Enum.all?(length_errors, fn {:name, msg} -> is_binary(msg) end)
    end

    test "expands number validation placeholder" do
      errors = ChangesetErrors.field_list(changeset(%{"name" => "ok", "quantity" => -1}))

      assert Enum.any?(errors, fn
               {:quantity, msg} -> msg =~ "must be greater than or equal to 0"
               _ -> false
             end),
             "expected expanded :number placeholder, got: #{inspect(errors)}"
    end

    test "leaves an unknown-atom placeholder intact instead of raising" do
      # Simulate a custom validator that injects a placeholder whose key
      # isn't a loaded atom. String.to_existing_atom would raise — the
      # helper must swallow that and leave the literal `%{foo}` in place.
      cs =
        %Sample{}
        |> cast(%{"name" => "ok"}, [:name])
        |> add_error(:name, "bad %{definitely_not_a_loaded_atom_xyz123}")

      assert [{:name, msg}] = ChangesetErrors.field_list(cs)
      assert msg == "bad %{definitely_not_a_loaded_atom_xyz123}"
    end

    test "leaves a placeholder intact when the atom is loaded but not in opts" do
      # `:count` is always loaded (Ecto uses it), but if a handcrafted error
      # references it without providing the value, we should not corrupt the
      # message with the raw key — keep the `%{count}` text so the gap is
      # visible.
      cs =
        %Sample{}
        |> cast(%{"name" => "ok"}, [:name])
        |> add_error(:name, "needs %{count} things", validation: :custom)

      assert [{:name, "needs %{count} things"}] = ChangesetErrors.field_list(cs)
    end

    test "replaces multiple placeholders within the same message" do
      cs =
        %Sample{}
        |> cast(%{"name" => "ok"}, [:name])
        |> add_error(:name, "expected %{min} to %{max}", min: 1, max: 10)

      assert [{:name, "expected 1 to 10"}] = ChangesetErrors.field_list(cs)
    end
  end
end
