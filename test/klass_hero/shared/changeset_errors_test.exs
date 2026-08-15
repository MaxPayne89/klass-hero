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

  describe "to_payload/1" do
    test "returns [] for a valid changeset" do
      assert ChangesetErrors.to_payload(changeset(%{"name" => "ok"})) == []
    end

    # The msgid is what gettext looks up, so expanding it here would leave the reader
    # with a string no catalog contains. Interpolation is the caller's second step.
    test "keeps the msgid unexpanded and hands the values over separately" do
      payload = ChangesetErrors.to_payload(changeset(%{"name" => "a"}))

      assert %{"msg" => "should be at least %{count} character(s)", "bindings" => %{"count" => 2}} =
               Enum.find(payload, &(&1["msg"] =~ "at least"))
    end

    test "names the field as a string so it survives jsonb" do
      assert [%{"field" => "name"} | _] = ChangesetErrors.to_payload(changeset(%{"name" => ""}))
    end

    test "round-trips through JSON unchanged" do
      payload = ChangesetErrors.to_payload(changeset(%{"name" => "a", "quantity" => -1}))

      assert payload == payload |> Jason.encode!() |> Jason.decode!()
    end

    # Ecto puts its own bookkeeping in opts (`validation: :length`, `kind: :min`), and a
    # custom validator can put anything there at all. Atoms stringify; a term with no
    # string form is dropped rather than allowed to break the render path.
    test "normalizes binding values to JSON-safe scalars" do
      cs =
        %Sample{}
        |> cast(%{"name" => "ok"}, [:name])
        |> add_error(:name, "bad", validation: :length, count: 3, term: {:awkwardly, "shaped"})

      assert [%{"bindings" => bindings}] = ChangesetErrors.to_payload(cs)
      assert bindings == %{"validation" => "length", "count" => 3}
    end

    test "keeps a count binding an integer so a plural lookup still works" do
      assert [%{"bindings" => %{"count" => count}} | _] =
               ChangesetErrors.to_payload(changeset(%{"name" => "a"}))

      assert is_integer(count)
    end
  end

  describe "gettext_bindings/1" do
    test "atom-keys the placeholders the errors catalog interpolates" do
      assert ChangesetErrors.gettext_bindings(%{"count" => 2, "number" => 1}) ==
               %{count: 2, number: 1}
    end

    # Gettext logs an error for any placeholder it cannot bind, so a key it does not need
    # is harmless but a key it does need being absent is not.
    test "drops keys that are not catalog placeholders" do
      assert ChangesetErrors.gettext_bindings(%{"validation" => "length", "kind" => "min"}) == %{}
    end

    test "returns an empty map when there is nothing to bind" do
      assert ChangesetErrors.gettext_bindings(%{}) == %{}
    end

    # The keys arrive from jsonb, so the conversion is a closed literal map — never
    # String.to_existing_atom, which raises once an atom is deleted in a later release.
    test "ignores a key it has no atom for rather than minting one" do
      refute Map.has_key?(ChangesetErrors.gettext_bindings(%{"totally_novel_key" => 1}), :totally_novel_key)
    end
  end

  describe "interpolate/2" do
    test "substitutes string-keyed bindings" do
      assert ChangesetErrors.interpolate("expected %{min} to %{max}", %{"min" => 1, "max" => 10}) ==
               "expected 1 to 10"
    end

    test "leaves a placeholder with no binding intact" do
      assert ChangesetErrors.interpolate("needs %{count} things", %{"validation" => "custom"}) ==
               "needs %{count} things"
    end

    test "returns the message untouched when there is nothing to bind" do
      assert ChangesetErrors.interpolate("can't be blank", %{}) == "can't be blank"
    end
  end
end
