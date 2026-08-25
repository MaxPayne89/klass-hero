defmodule KlassHero.Messaging.AuthorizationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.Authorization
  alias KlassHero.ProviderFixtures

  describe "authorize_admin/1" do
    test "authorizes a platform admin" do
      assert :ok = Authorization.authorize_admin(admin_scope_fixture())
    end

    test "refuses a non-admin scope" do
      assert {:error, :unauthorized} = Authorization.authorize_admin(user_scope_fixture())
    end
  end

  describe "authorize_provider_owner/1" do
    test "authorizes an owner and hands back the provider it resolved" do
      provider = ProviderFixtures.provider_profile_fixture()
      scope = %Scope{user: user_fixture(), provider: provider}

      assert {:ok, provider_id} = Authorization.authorize_provider_owner(scope)
      assert provider_id == provider.id
    end

    # The gate that separates this from `resolve_acting_provider/2`, which accepts a
    # staff scope on purpose. Accepting one here would let a staff member read their
    # coworkers' private threads with parents.
    test "refuses a staff scope of the very provider it works for" do
      provider = ProviderFixtures.provider_profile_fixture()
      user = user_fixture(intended_roles: [:staff])
      staff = ProviderFixtures.staff_member_fixture(provider_id: provider.id, user_id: user.id)

      assert {:error, :unauthorized} =
               Authorization.authorize_provider_owner(%Scope{user: user, staff_member: staff})
    end

    test "refuses a scope carrying neither profile" do
      assert {:error, :unauthorized} = Authorization.authorize_provider_owner(user_scope_fixture())
    end
  end
end
