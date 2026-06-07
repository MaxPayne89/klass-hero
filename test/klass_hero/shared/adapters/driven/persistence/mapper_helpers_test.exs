defmodule KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpersTest do
  use ExUnit.Case, async: true

  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers

  describe "string_to_tier/2" do
    test "returns the atom for a valid parent tier string" do
      assert MapperHelpers.string_to_tier("explorer", :explorer) == :explorer
      assert MapperHelpers.string_to_tier("active", :explorer) == :active
    end

    test "returns the default for a former provider tier string (ADR-0004)" do
      assert MapperHelpers.string_to_tier("starter", :explorer) == :explorer
      assert MapperHelpers.string_to_tier("business_plus", :explorer) == :explorer
    end

    test "returns the default when the string is nil" do
      assert MapperHelpers.string_to_tier(nil, :explorer) == :explorer
    end

    test "returns the default for an unknown tier string" do
      assert MapperHelpers.string_to_tier("unknown_tier", :explorer) == :explorer
    end

    test "returns the default for an empty string" do
      assert MapperHelpers.string_to_tier("", :explorer) == :explorer
    end

    test "does not create new atoms from arbitrary strings" do
      # Verify the function is safe and won't raise for non-existent atoms
      result = MapperHelpers.string_to_tier("definitely_not_an_existing_atom_xyz123", :explorer)

      assert result == :explorer
    end

    test "returns the default for an existing atom that is not a valid tier" do
      # Trigger: :ok exists in the BEAM atom table but is not in @all_tiers
      # Why: covers the allowlist check, not just the rescue path
      assert MapperHelpers.string_to_tier("ok", :explorer) == :explorer
    end
  end

  describe "tier_to_string/2" do
    test "converts a parent tier atom to its string representation" do
      assert MapperHelpers.tier_to_string(:explorer, "explorer") == "explorer"
      assert MapperHelpers.tier_to_string(:active, "explorer") == "active"
    end

    test "returns the default string when tier is nil" do
      assert MapperHelpers.tier_to_string(nil, "explorer") == "explorer"
    end
  end

  describe "normalize_subscription_tier/1" do
    test "converts atom subscription_tier to a string" do
      attrs = %{subscription_tier: :explorer, name: "Alice"}

      assert MapperHelpers.normalize_subscription_tier(attrs) == %{
               subscription_tier: "explorer",
               name: "Alice"
             }
    end

    test "leaves attrs unchanged when subscription_tier key is absent" do
      attrs = %{name: "Alice"}

      assert MapperHelpers.normalize_subscription_tier(attrs) == %{name: "Alice"}
    end

    test "leaves attrs unchanged when subscription_tier is nil" do
      attrs = %{subscription_tier: nil, name: "Alice"}

      assert MapperHelpers.normalize_subscription_tier(attrs) == %{
               subscription_tier: nil,
               name: "Alice"
             }
    end

    test "leaves attrs unchanged when subscription_tier is already a string" do
      attrs = %{subscription_tier: "explorer"}

      assert MapperHelpers.normalize_subscription_tier(attrs) == %{subscription_tier: "explorer"}
    end
  end

  describe "normalize_atom_field/2" do
    test "converts atom value to string for arbitrary key" do
      attrs = %{originated_from: :staff_invite, name: "Alice"}

      assert MapperHelpers.normalize_atom_field(attrs, :originated_from) == %{
               originated_from: "staff_invite",
               name: "Alice"
             }
    end

    test "leaves attrs unchanged when key is absent" do
      attrs = %{name: "Alice"}

      assert MapperHelpers.normalize_atom_field(attrs, :originated_from) == %{name: "Alice"}
    end

    test "leaves attrs unchanged when value is nil" do
      attrs = %{originated_from: nil, name: "Alice"}

      assert MapperHelpers.normalize_atom_field(attrs, :originated_from) == %{
               originated_from: nil,
               name: "Alice"
             }
    end

    test "leaves attrs unchanged when value is already a string" do
      attrs = %{originated_from: "direct"}

      assert MapperHelpers.normalize_atom_field(attrs, :originated_from) == %{
               originated_from: "direct"
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
