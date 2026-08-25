defmodule KlassHero.Family.ExportDataForUserTest do
  @moduledoc """
  Tests for Family.export_data_for_user/1.

  Verifies GDPR data export includes children and full consent history
  (including withdrawn records) for the user's parent profile.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Family

  describe "export_data_for_user/1" do
    test "returns children with nested consents for parent with full data" do
      user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: user.id)

      {child, _parent} =
        insert_child_with_guardian(
          parent: parent,
          first_name: "Emma",
          last_name: "Smith",
          allergies: "Peanuts",
          emergency_contact: "+49123456",
          support_needs: "Wheelchair access"
        )

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "provider_data_sharing"
      )

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "photo_marketing"
      )

      result = Family.export_data_for_user(user.id)

      assert %{children: [exported_child]} = result
      assert exported_child.first_name == "Emma"
      assert exported_child.last_name == "Smith"
      assert exported_child.allergies == "Peanuts"
      assert exported_child.emergency_contact == "+49123456"
      assert exported_child.support_needs == "Wheelchair access"
      assert exported_child.id == child.id
      # The export contract is ISO8601 text, so parseability is the property that matters
      # to a consumer — "is a string" would hold for any serialisation bug.
      assert {:ok, %Date{}} = Date.from_iso8601(exported_child.date_of_birth)
      assert {:ok, %DateTime{}, 0} = DateTime.from_iso8601(exported_child.created_at)
      assert {:ok, %DateTime{}, 0} = DateTime.from_iso8601(exported_child.updated_at)

      assert length(exported_child.consents) == 2
      consent_types = Enum.map(exported_child.consents, & &1.consent_type)
      assert "provider_data_sharing" in consent_types
      assert "photo_marketing" in consent_types

      first_consent = Enum.at(exported_child.consents, 0)
      assert first_consent.id in Enum.map(exported_child.consents, & &1.id)
      assert {:ok, %DateTime{}, 0} = DateTime.from_iso8601(first_consent.granted_at)
      assert {:ok, %DateTime{}, 0} = DateTime.from_iso8601(first_consent.created_at)
      assert {:ok, %DateTime{}, 0} = DateTime.from_iso8601(first_consent.updated_at)
      assert is_nil(first_consent.withdrawn_at)
    end

    test "includes withdrawn consents in export for audit history" do
      user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: user.id)
      {child, _parent} = insert_child_with_guardian(parent: parent)

      active_consent =
        insert(:consent_schema,
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "provider_data_sharing"
        )

      _withdrawn_consent =
        insert(:consent_schema,
          parent_id: parent.id,
          child_id: child.id,
          consent_type: "photo_marketing",
          withdrawn_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      result = Family.export_data_for_user(user.id)

      assert %{children: [exported_child]} = result
      # Trigger: both active and withdrawn consents must appear
      # Why: GDPR requires full audit trail of consent history
      assert length(exported_child.consents) == 2

      withdrawn =
        Enum.find(exported_child.consents, &(&1.consent_type == "photo_marketing"))

      assert {:ok, %DateTime{}, 0} = DateTime.from_iso8601(withdrawn.withdrawn_at)

      active =
        Enum.find(exported_child.consents, &(&1.id == active_consent.id))

      assert is_nil(active.withdrawn_at)
    end

    test "returns children with empty consents list when no consents exist" do
      user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: user.id)
      {_child, _parent} = insert_child_with_guardian(parent: parent)

      result = Family.export_data_for_user(user.id)

      assert %{children: [exported_child]} = result
      assert exported_child.consents == []
    end

    test "returns empty children list when parent has no children" do
      user = AccountsFixtures.user_fixture()
      _parent = insert(:parent_profile_schema, identity_id: user.id)

      result = Family.export_data_for_user(user.id)

      assert result == %{children: []}
    end

    test "returns empty map when user has no parent profile" do
      user = AccountsFixtures.user_fixture()

      result = Family.export_data_for_user(user.id)

      assert result == %{}
    end

    test "exports multiple children each with their own consents" do
      user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: user.id)

      {child_a, _parent} =
        insert_child_with_guardian(
          parent: parent,
          first_name: "Alice",
          last_name: "Doe"
        )

      {child_b, _parent} =
        insert_child_with_guardian(
          parent: parent,
          first_name: "Bob",
          last_name: "Doe"
        )

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child_a.id,
        consent_type: "photo_marketing"
      )

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child_b.id,
        consent_type: "provider_data_sharing"
      )

      result = Family.export_data_for_user(user.id)

      assert %{children: children} = result
      assert length(children) == 2

      alice = Enum.find(children, &(&1.first_name == "Alice"))
      bob = Enum.find(children, &(&1.first_name == "Bob"))

      assert length(alice.consents) == 1
      assert Enum.at(alice.consents, 0).consent_type == "photo_marketing"

      assert length(bob.consents) == 1
      assert Enum.at(bob.consents, 0).consent_type == "provider_data_sharing"
    end
  end
end
