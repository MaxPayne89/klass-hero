defmodule KlassHero.Accounts.Adapters.Driven.Persistence.Repositories.UserRepositoryAppendRoleTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts.Adapters.Driven.Persistence.Repositories.UserRepository
  alias KlassHero.Accounts.User

  defp reload_roles(user_id), do: Repo.get!(User, user_id).intended_roles

  describe "append_intended_role/2" do
    test "persists the appended role, preserving existing ones" do
      user = user_fixture(intended_roles: [:parent])

      assert {:ok, updated} = UserRepository.append_intended_role(user, :staff)

      assert updated.intended_roles == [:parent, :staff]
      assert reload_roles(user.id) == [:parent, :staff]
    end

    test "is idempotent across repeated appends" do
      user = user_fixture(intended_roles: [:staff])

      assert {:ok, _} = UserRepository.append_intended_role(user, :staff)
      assert {:ok, _} = UserRepository.append_intended_role(user, :staff)

      assert reload_roles(user.id) == [:staff]
    end
  end
end
