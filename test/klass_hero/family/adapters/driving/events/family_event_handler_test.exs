defmodule KlassHero.Family.Adapters.Driving.Events.FamilyEventHandlerTest do
  @moduledoc """
  Tests for FamilyEventHandler integration event handling.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Accounts.Domain.Events.AccountsIntegrationEvents
  alias KlassHero.AccountsFixtures
  alias KlassHero.Family.Adapters.Driving.Events.FamilyEventHandler
  alias KlassHero.Family.Child
  alias KlassHero.Family.Consent

  describe "handle_event/1 for :user_anonymized" do
    setup do
      setup_test_integration_events()
      :ok
    end

    test "anonymizes children and deletes consents for the user" do
      user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: user.id)

      {child, _parent} =
        insert_child_with_guardian(
          parent: parent,
          first_name: "Emma",
          last_name: "Smith",
          emergency_contact: "+49123",
          support_needs: "Extra help",
          allergies: "Nuts"
        )

      insert(:consent_schema,
        parent_id: parent.id,
        child_id: child.id,
        consent_type: "provider_data_sharing"
      )

      event =
        AccountsIntegrationEvents.user_anonymized(
          user.id,
          %{anonymized_email: "deleted_#{user.id}@anonymized.local"}
        )

      assert :ok == FamilyEventHandler.handle_event(event)

      reloaded = Repo.get!(Child, child.id)
      assert reloaded.first_name == "Anonymized"
      assert reloaded.last_name == "Child"
      assert is_nil(reloaded.emergency_contact)
      assert is_nil(reloaded.support_needs)
      assert is_nil(reloaded.allergies)

      assert Repo.aggregate(
               from(c in Consent, where: c.child_id == ^child.id),
               :count
             ) == 0
    end

    test "publishes child_data_anonymized event per child" do
      user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: user.id)
      {child, _parent} = insert_child_with_guardian(parent: parent)

      event =
        AccountsIntegrationEvents.user_anonymized(
          user.id,
          %{anonymized_email: "deleted_#{user.id}@anonymized.local"}
        )

      assert :ok == FamilyEventHandler.handle_event(event)

      child_event = assert_integration_event_published(:child_data_anonymized)
      assert child_event.entity_id == child.id
    end

    test "returns :ok for user without parent profile" do
      user = AccountsFixtures.user_fixture()

      event =
        AccountsIntegrationEvents.user_anonymized(
          user.id,
          %{anonymized_email: "deleted_#{user.id}@anonymized.local"}
        )

      assert :ok == FamilyEventHandler.handle_event(event)
    end
  end

  describe "subscribed_events/0" do
    test "includes :user_anonymized" do
      assert :user_anonymized in FamilyEventHandler.subscribed_events()
    end

    test "includes :user_registered" do
      assert :user_registered in FamilyEventHandler.subscribed_events()
    end

    test "includes :user_confirmed" do
      assert :user_confirmed in FamilyEventHandler.subscribed_events()
    end
  end

  describe "handle_event/1 for :user_confirmed" do
    test "creates parent profile when 'parent' in intended_roles" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:parent])

      event = build_user_confirmed_event(user)
      assert :ok = FamilyEventHandler.handle_event(event)

      assert {:ok, _profile} = KlassHero.Family.get_parent_by_identity(user.id)
    end

    test "returns :ok when parent profile already exists (idempotent)" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:parent])

      # First call creates the profile
      registered_event = build_user_registered_event(user)
      assert :ok = FamilyEventHandler.handle_event(registered_event)

      # Second call via user_confirmed is idempotent
      confirmed_event = build_user_confirmed_event(user)
      assert :ok = FamilyEventHandler.handle_event(confirmed_event)
    end

    test "ignores event when 'parent' not in intended_roles" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      event = build_user_confirmed_event(user, intended_roles: ["provider"])
      assert :ignore = FamilyEventHandler.handle_event(event)
    end
  end

  defp build_user_registered_event(user, opts \\ []) do
    intended_roles = Keyword.get(opts, :intended_roles, ["parent"])

    %{
      event_type: :user_registered,
      entity_id: user.id,
      payload: %{
        intended_roles: intended_roles,
        name: user.name || "Test User"
      }
    }
  end

  defp build_user_confirmed_event(user, opts \\ []) do
    intended_roles = Keyword.get(opts, :intended_roles, ["parent"])

    %{
      event_type: :user_confirmed,
      entity_id: user.id,
      payload: %{
        intended_roles: intended_roles,
        name: user.name || "Test User"
      }
    }
  end
end
