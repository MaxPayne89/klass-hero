defmodule KlassHero.Provider.StaffMembershipsQueryTest do
  @moduledoc """
  Public-API tests for Provider.list_active_staff_memberships/1 (#969
  staff-context switcher picker data).
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider
  alias KlassHero.Provider.ReadModels.StaffMembership
  alias KlassHero.ProviderFixtures

  describe "list_active_staff_memberships/1" do
    test "returns all active memberships with business names, selection-ordered" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      employer = ProviderFixtures.provider_profile_fixture(%{business_name: "Employer GmbH"})

      own_business =
        ProviderFixtures.provider_profile_fixture(%{
          identity_id: user.id,
          business_name: "Own Thing"
        })

      ProviderFixtures.staff_member_fixture(%{provider_id: employer.id, user_id: user.id})
      ProviderFixtures.staff_member_fixture(%{provider_id: own_business.id, user_id: user.id})

      assert {:ok, [first, second]} = Provider.list_active_staff_memberships(user.id)

      # Same ordering as scope resolution: employer-first default, so the head
      # of this list is exactly the row the scope carries.
      assert %StaffMembership{provider_id: provider_id, business_name: "Employer GmbH"} = first
      assert provider_id == employer.id
      assert %StaffMembership{business_name: "Own Thing"} = second
      assert second.provider_id == own_business.id
    end

    test "excludes inactive rows and rows belonging to other users" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      other_user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      employer = ProviderFixtures.provider_profile_fixture()
      former = ProviderFixtures.provider_profile_fixture()

      kept =
        ProviderFixtures.staff_member_fixture(%{provider_id: employer.id, user_id: user.id})

      ProviderFixtures.staff_member_fixture(%{
        provider_id: former.id,
        user_id: user.id,
        active: false
      })

      ProviderFixtures.staff_member_fixture(%{provider_id: employer.id, user_id: other_user.id})

      assert {:ok, [only]} = Provider.list_active_staff_memberships(user.id)
      assert only.staff_member_id == kept.id
    end

    test "returns an empty list for a user with no memberships" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      assert {:ok, []} = Provider.list_active_staff_memberships(user.id)
    end
  end
end
