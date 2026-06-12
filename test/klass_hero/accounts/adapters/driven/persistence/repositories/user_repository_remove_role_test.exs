defmodule KlassHero.Accounts.Adapters.Driven.Persistence.Repositories.UserRepositoryRemoveRoleTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts.Adapters.Driven.Persistence.Repositories.UserRepository
  alias KlassHero.Accounts.User

  defp reload_roles(user_id), do: Repo.get!(User, user_id).intended_roles

  describe "remove_intended_role/2" do
    test "persists the removal, preserving the other roles" do
      user = user_fixture(intended_roles: [:provider, :staff])

      assert {:ok, updated} = UserRepository.remove_intended_role(user, :staff)

      assert updated.intended_roles == [:provider]
      assert reload_roles(user.id) == [:provider]
    end

    test "is idempotent when the role is already absent" do
      user = user_fixture(intended_roles: [:provider])

      assert {:ok, _} = UserRepository.remove_intended_role(user, :staff)

      assert reload_roles(user.id) == [:provider]
    end
  end
end
