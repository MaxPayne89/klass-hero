defmodule KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpersTest do
  use KlassHero.DataCase, async: true

  import Ecto.Query

  alias KlassHero.Accounts.Adapters.Driven.Persistence.Mappers.UserMapper
  alias KlassHero.Accounts.User
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers

  describe "get_by_id/3" do
    test "returns {:ok, domain_struct} when record exists" do
      user = KlassHero.AccountsFixtures.user_fixture()

      assert {:ok, domain} = RepositoryHelpers.get_by_id(User, user.id, UserMapper)
      assert domain.id == user.id
      assert domain.email == user.email
    end

    test "returns {:error, :not_found} when record does not exist" do
      assert {:error, :not_found} =
               RepositoryHelpers.get_by_id(User, Ecto.UUID.generate(), UserMapper)
    end
  end

  describe "get_schema_by_uuid/2" do
    test "returns {:ok, schema} when record exists" do
      user = KlassHero.AccountsFixtures.user_fixture()

      assert {:ok, schema} = RepositoryHelpers.get_schema_by_uuid(User, user.id)
      assert schema.id == user.id
    end

    test "returns {:error, :not_found} when the UUID is well-formed but absent" do
      assert {:error, :not_found} =
               RepositoryHelpers.get_schema_by_uuid(User, Ecto.UUID.generate())
    end

    test "returns {:error, :not_found} for a malformed UUID instead of crashing" do
      assert {:error, :not_found} = RepositoryHelpers.get_schema_by_uuid(User, "not-a-uuid")
    end
  end

  describe "get_by_uuid/3" do
    test "returns {:ok, domain_struct} when record exists" do
      user = KlassHero.AccountsFixtures.user_fixture()

      assert {:ok, domain} = RepositoryHelpers.get_by_uuid(User, user.id, UserMapper)
      assert domain.id == user.id
    end

    test "returns {:error, :not_found} for a malformed UUID instead of crashing" do
      assert {:error, :not_found} = RepositoryHelpers.get_by_uuid(User, "not-a-uuid", UserMapper)
    end
  end

  describe "fetch_one/2" do
    test "returns {:ok, domain_struct} for a query that matches one record" do
      user = KlassHero.AccountsFixtures.user_fixture()
      query = from(u in User, where: u.id == ^user.id)

      assert {:ok, domain} = RepositoryHelpers.fetch_one(query, UserMapper)
      assert domain.id == user.id
    end

    test "returns {:error, :not_found} when the query matches nothing" do
      query = from(u in User, where: u.id == ^Ecto.UUID.generate())

      assert {:error, :not_found} = RepositoryHelpers.fetch_one(query, UserMapper)
    end
  end
end
