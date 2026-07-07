defmodule KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpersTest do
  use ExUnit.Case, async: true

  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers

  describe "normalize_atom_field/2" do
    test "converts atom value to string for arbitrary key" do
      attrs = %{profile_status: :draft, name: "Alice"}

      assert MapperHelpers.normalize_atom_field(attrs, :profile_status) == %{
               profile_status: "draft",
               name: "Alice"
             }
    end

    test "leaves attrs unchanged when key is absent" do
      attrs = %{name: "Alice"}

      assert MapperHelpers.normalize_atom_field(attrs, :profile_status) == %{name: "Alice"}
    end

    test "leaves attrs unchanged when value is nil" do
      attrs = %{profile_status: nil, name: "Alice"}

      assert MapperHelpers.normalize_atom_field(attrs, :profile_status) == %{
               profile_status: nil,
               name: "Alice"
             }
    end

    test "leaves attrs unchanged when value is already a string" do
      attrs = %{profile_status: "active"}

      assert MapperHelpers.normalize_atom_field(attrs, :profile_status) == %{
               profile_status: "active"
             }
    end
  end

  describe "maybe_add_id/2" do
    test "adds the id to the attrs map when id is present" do
      attrs = %{name: "Alice"}

      assert MapperHelpers.maybe_add_id(attrs, "some-uuid") == %{id: "some-uuid", name: "Alice"}
    end

    test "returns attrs unchanged when id is nil" do
      attrs = %{name: "Alice"}

      assert MapperHelpers.maybe_add_id(attrs, nil) == %{name: "Alice"}
    end

    test "works with empty attrs map" do
      assert MapperHelpers.maybe_add_id(%{}, "abc-123") == %{id: "abc-123"}
    end

    test "overwrites existing id when a new id is provided" do
      attrs = %{id: "old-id", name: "Alice"}

      assert MapperHelpers.maybe_add_id(attrs, "new-id") == %{id: "new-id", name: "Alice"}
    end
  end

  describe "to_domain_list/2" do
    defmodule TestMapper do
      # Trigger: we need a mapper module that transforms maps to demonstrate to_domain_list/2
      # Why: using plain maps avoids struct compilation ordering issues in test modules
      # Outcome: clean, isolated test of the collection mapping behavior
      def to_domain(%{id: id, name: name}) do
        %{id: id, name: String.upcase(name)}
      end
    end

    test "converts list of schemas using the given mapper module" do
      schemas = [
        %{id: 1, name: "first"},
        %{id: 2, name: "second"}
      ]

      result = MapperHelpers.to_domain_list(schemas, TestMapper)

      assert [%{id: 1, name: "FIRST"}, %{id: 2, name: "SECOND"}] = result
    end

    test "returns empty list for empty input" do
      assert [] == MapperHelpers.to_domain_list([], TestMapper)
    end

    test "preserves order of input list" do
      schemas = [
        %{id: 3, name: "third"},
        %{id: 1, name: "first"},
        %{id: 2, name: "second"}
      ]

      result = MapperHelpers.to_domain_list(schemas, TestMapper)

      assert [%{id: 3}, %{id: 1}, %{id: 2}] = result
    end

    test "delegates to mapper module's to_domain/1 for each element" do
      schema = %{id: 42, name: "test"}

      [domain] = MapperHelpers.to_domain_list([schema], TestMapper)

      assert domain.id == 42
      assert domain.name == "TEST"
    end
  end

  describe "normalize_keys/1" do
    test "passes through atom keys unchanged" do
      payload = %{email: "test@example.com", name: "Jane"}
      assert MapperHelpers.normalize_keys(payload) == payload
    end

    test "converts known string keys to atoms" do
      payload = %{"email" => "test@example.com", "name" => "Jane"}

      result = MapperHelpers.normalize_keys(payload)

      assert result == %{email: "test@example.com", name: "Jane"}
    end

    test "handles mixed atom and string keys" do
      payload = Map.put(%{email: "test@example.com"}, "name", "Jane")

      result = MapperHelpers.normalize_keys(payload)

      assert result == %{email: "test@example.com", name: "Jane"}
    end

    test "keeps unknown string keys as strings instead of crashing" do
      # Atoms :email and :name already exist; "definitely_not_an_atom_xyz" does not
      payload = %{"email" => "test@example.com", "definitely_not_an_atom_xyz" => "unknown"}

      result = MapperHelpers.normalize_keys(payload)

      assert result[:email] == "test@example.com"
      assert result["definitely_not_an_atom_xyz"] == "unknown"
    end
  end
end
