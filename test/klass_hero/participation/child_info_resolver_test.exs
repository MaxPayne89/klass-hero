defmodule KlassHero.Participation.ChildInfoResolverTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Participation.ChildInfoResolver

  describe "resolve_child_info/1" do
    test "returns name and safety info when child has active provider_data_sharing consent" do
      parent = factory_insert(:parent_profile_schema)

      {child, _parent} =
        KlassHero.Factory.insert_child_with_guardian(
          parent: parent,
          first_name: "Jane",
          last_name: "Smith",
          allergies: "Peanuts",
          support_needs: "ADHD accommodations",
          emergency_contact: "+49 123 456789"
        )

      factory_insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "provider_data_sharing"
      )

      assert {:ok, info} = ChildInfoResolver.resolve_child_info(child.id)
      assert info.first_name == "Jane"
      assert info.last_name == "Smith"
      assert info.allergies == "Peanuts"
      assert info.support_needs == "ADHD accommodations"
      assert info.emergency_contact == "+49 123 456789"
    end

    test "returns name but nil safety fields when child has no active consent" do
      child =
        factory_insert(:child_schema,
          first_name: "Alice",
          last_name: "Jones",
          allergies: "Peanuts",
          support_needs: "ADHD accommodations"
        )

      assert {:ok, info} = ChildInfoResolver.resolve_child_info(child.id)
      assert info.first_name == "Alice"
      assert info.last_name == "Jones"
      assert info.allergies == nil
      assert info.support_needs == nil
      assert info.emergency_contact == nil
    end

    test "returns nil safety fields when child has consent but nil optional fields" do
      parent = factory_insert(:parent_profile_schema)

      {child, _parent} =
        KlassHero.Factory.insert_child_with_guardian(
          parent: parent,
          allergies: nil,
          support_needs: nil,
          emergency_contact: nil
        )

      factory_insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "provider_data_sharing"
      )

      assert {:ok, info} = ChildInfoResolver.resolve_child_info(child.id)
      assert info.allergies == nil
      assert info.support_needs == nil
      assert info.emergency_contact == nil
    end

    test "returns nil safety fields when consent has been withdrawn" do
      parent = factory_insert(:parent_profile_schema)

      {child, _parent} =
        KlassHero.Factory.insert_child_with_guardian(
          parent: parent,
          first_name: "Bob",
          last_name: "Brown",
          allergies: "Gluten"
        )

      factory_insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "provider_data_sharing",
        withdrawn_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      assert {:ok, info} = ChildInfoResolver.resolve_child_info(child.id)
      assert info.first_name == "Bob"
      assert info.last_name == "Brown"
      assert info.allergies == nil
    end

    test "returns :child_not_found when child does not exist" do
      non_existent_id = Ecto.UUID.generate()

      assert {:error, :child_not_found} = ChildInfoResolver.resolve_child_info(non_existent_id)
    end

    test "returns :child_not_found for invalid UUID format" do
      invalid_id = "not-a-valid-uuid"

      assert {:error, :child_not_found} = ChildInfoResolver.resolve_child_info(invalid_id)
    end
  end

  defp factory_insert(factory, attrs \\ []) do
    KlassHero.Factory.insert(factory, attrs)
  end
end
