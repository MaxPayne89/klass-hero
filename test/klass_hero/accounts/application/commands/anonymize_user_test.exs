defmodule KlassHero.Accounts.Application.Commands.AnonymizeUserTest do
  @moduledoc """
  Integration tests for AnonymizeUser use case.

  Verifies GDPR anonymization orchestration: a valid user's PII is scrubbed,
  and nil input returns an :user_not_found error.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts.Adapters.Driven.Persistence.Repositories.UserRepository
  alias KlassHero.Accounts.Application.Commands.AnonymizeUser
  alias KlassHero.Accounts.Domain.Models.User

  describe "execute/1 — success path" do
    test "returns anonymized domain User" do
      user = user_fixture()

      assert {:ok, %User{} = anonymized} = AnonymizeUser.execute(user)
      assert anonymized.id == user.id
      assert anonymized.email == "deleted_#{user.id}@anonymized.local"
      assert anonymized.name == "Deleted User"
    end

    test "persists anonymized PII to the database" do
      user = user_fixture()

      {:ok, _} = AnonymizeUser.execute(user)

      assert {:ok, persisted} = UserRepository.get_by_id(user.id)
      assert persisted.email == "deleted_#{user.id}@anonymized.local"
      assert persisted.name == "Deleted User"
    end
  end

  describe "execute/1 — nil guard" do
    test "returns :user_not_found for nil user" do
      assert {:error, :user_not_found} = AnonymizeUser.execute(nil)
    end
  end
end
