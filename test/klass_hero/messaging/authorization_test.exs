defmodule KlassHero.Messaging.AuthorizationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Messaging.Authorization

  describe "authorize_admin/1" do
    test "authorizes a platform admin" do
      assert :ok = Authorization.authorize_admin(admin_scope_fixture())
    end

    test "refuses a non-admin scope" do
      assert {:error, :unauthorized} = Authorization.authorize_admin(user_scope_fixture())
    end
  end
end
