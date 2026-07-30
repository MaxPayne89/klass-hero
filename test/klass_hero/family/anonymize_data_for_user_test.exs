defmodule KlassHero.Family.AnonymizeDataForUserTest do
  @moduledoc """
  Tests for Family.anonymize_data_for_user/1.

  Verifies GDPR account anonymization cascades to children and consents
  in the Family context, and publishes integration events for downstream contexts.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Family
  alias KlassHero.Family.Child
  alias KlassHero.Family.Consent

  describe "anonymize_data_for_user/1" do
    setup do
      setup_test_integration_events()
      :ok
    end

    test "anonymizes child PII fields" do
      user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: user.id)

      {child, _parent} =
        insert_child_with_guardian(
          parent: parent,
          first_name: "Emma",
          last_name: "Smith",
          emergency_contact: "+49123456",
          support_needs: "Wheelchair access",
          allergies: "Peanuts"
        )

      {:ok, _summary} = Family.anonymize_data_for_user(user.id)

      reloaded = Repo.get!(Child, child.id)
      assert reloaded.first_name == "Anonymized"
      assert reloaded.last_name == "Child"
      assert is_nil(reloaded.emergency_contact)
      assert is_nil(reloaded.support_needs)
      assert is_nil(reloaded.allergies)
    end

    test "anonymizes date_of_birth after anonymization" do
      user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: user.id)

      {child, _parent} =
        insert_child_with_guardian(
          parent: parent,
          date_of_birth: ~D[2018-03-15]
        )

      {:ok, _summary} = Family.anonymize_data_for_user(user.id)

      reloaded = Repo.get!(Child, child.id)
      assert is_nil(reloaded.date_of_birth)
    end

    test "deletes all consents for each child" do
      user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: user.id)
      {child, _parent} = insert_child_with_guardian(parent: parent)

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "provider_data_sharing"
      )

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "photo_marketing",
        withdrawn_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      # Verify consents exist before
      assert Repo.aggregate(
               from(c in Consent, where: c.child_id == ^child.id),
               :count
             ) == 2

      {:ok, summary} = Family.anonymize_data_for_user(user.id)

      assert summary.consents_deleted == 2

      assert Repo.aggregate(
               from(c in Consent, where: c.child_id == ^child.id),
               :count
             ) == 0
    end

    test "publishes child_data_anonymized integration event per child" do
      user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: user.id)
      {child, _parent} = insert_child_with_guardian(parent: parent)

      {:ok, _summary} = Family.anonymize_data_for_user(user.id)

      event = assert_integration_event_published(:child_data_anonymized)
      assert event.entity_id == child.id
      assert event.payload.child_id == child.id
      assert event.source_context == :family
    end

    test "handles multiple children — all anonymized with consents deleted and events published" do
      user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: user.id)

      {child_a, _parent} = insert_child_with_guardian(parent: parent, first_name: "Alice")
      {child_b, _parent} = insert_child_with_guardian(parent: parent, first_name: "Bob")

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child_a.id,
        consent_type: "provider_data_sharing"
      )

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child_b.id,
        consent_type: "photo_marketing"
      )

      {:ok, summary} = Family.anonymize_data_for_user(user.id)

      assert summary.children_anonymized == 2
      assert summary.consents_deleted == 2

      reloaded_a = Repo.get!(Child, child_a.id)
      reloaded_b = Repo.get!(Child, child_b.id)

      assert reloaded_a.first_name == "Anonymized"
      assert reloaded_b.first_name == "Anonymized"

      # Verify one child_data_anonymized integration event per child
      events = get_published_integration_events()

      child_events =
        Enum.filter(events, &(&1.event_type == :child_data_anonymized))

      assert length(child_events) == 2

      event_child_ids = MapSet.new(child_events, & &1.entity_id)
      assert MapSet.member?(event_child_ids, child_a.id)
      assert MapSet.member?(event_child_ids, child_b.id)
    end

    test "returns :no_data for user without parent profile" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, :no_data} = Family.anonymize_data_for_user(user.id)
    end

    # The old contract was the inverse of this one: publishing happened after each
    # child was anonymized, so a publish failure left the data anonymized and the
    # downstream contexts un-notified, and the test pinned that split.
    #
    # The GDPR cascade's gate was asking "were the downstream contexts told?" and
    # answering it with a dispatch result. Staging inside each child's own
    # transaction answers it at commit, so the two cannot come apart — a child is
    # anonymized only if the event saying so is durable.
    test "each anonymized child stages the event announcing it" do
      user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: user.id)

      {child, _parent} = insert_child_with_guardian(parent: parent, first_name: "Emma", last_name: "Smith")

      assert {:ok, %{children_anonymized: 1}} = Family.anonymize_data_for_user(user.id)

      assert %{first_name: "Anonymized"} = Repo.get!(Child, child.id)

      child_id = child.id
      assert %{payload: %{child_id: ^child_id}} = assert_integration_event_published(:child_data_anonymized)
    end
  end
end
