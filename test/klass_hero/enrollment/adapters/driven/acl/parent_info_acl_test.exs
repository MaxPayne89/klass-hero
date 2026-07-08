defmodule KlassHero.Enrollment.Adapters.Driven.ACL.ParentInfoACLTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driven.ACL.ParentInfoACL

  describe "get_parents_by_ids/1" do
    test "returns parent info maps with id and identity_id" do
      parent = insert(:parent_profile_schema)

      [result] = ParentInfoACL.get_parents_by_ids([parent.id])

      assert result.id == to_string(parent.id)
      assert result.identity_id == to_string(parent.identity_id)
    end

    test "returns empty list for empty input" do
      assert ParentInfoACL.get_parents_by_ids([]) == []
    end

    test "returns only id and identity_id fields" do
      parent = insert(:parent_profile_schema)

      [result] = ParentInfoACL.get_parents_by_ids([parent.id])

      assert Map.keys(result) |> Enum.sort() == [:id, :identity_id]
    end

    test "silently excludes non-existent IDs" do
      parent = insert(:parent_profile_schema)

      result = ParentInfoACL.get_parents_by_ids([parent.id, Ecto.UUID.generate()])

      assert length(result) == 1
      assert hd(result).id == to_string(parent.id)
    end
  end

  describe "resolve_identity_id/1" do
    test "returns the parent_id for a known identity_id" do
      parent = insert(:parent_profile_schema)

      assert ParentInfoACL.resolve_identity_id(parent.identity_id) == to_string(parent.id)
    end

    test "returns nil when no parent profile exists for the identity_id" do
      assert ParentInfoACL.resolve_identity_id(Ecto.UUID.generate()) == nil
    end
  end
end
