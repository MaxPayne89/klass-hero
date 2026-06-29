defmodule KlassHero.Accounts.AnonymizeUserTest do
  @moduledoc """
  Integration tests for `Accounts.anonymize_user/1`.

  Verifies GDPR anonymization orchestration: a valid user's PII is scrubbed,
  and nil input returns an :user_not_found error.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts
  # Auth uses phx.gen.auth: KlassHero.Accounts.User (the Ecto schema) is the
  # canonical user type the context returns — not a separate domain model.
  alias KlassHero.Accounts.User

  describe "anonymize_user/1 — success path" do
    test "returns the anonymized User" do
      user = user_fixture()

      assert {:ok, %User{} = anonymized} = Accounts.anonymize_user(user)
      assert anonymized.id == user.id
      assert anonymized.email == "deleted_#{user.id}@anonymized.local"
      assert anonymized.name == "Deleted User"
    end

    test "persists anonymized PII to the database" do
      user = user_fixture()

      {:ok, _} = Accounts.anonymize_user(user)

      persisted = Accounts.get_user!(user.id)
      assert persisted.email == "deleted_#{user.id}@anonymized.local"
      assert persisted.name == "Deleted User"
    end
  end

  describe "anonymize_user/1 — nil guard" do
    test "returns :user_not_found for nil user" do
      assert {:error, :user_not_found} = Accounts.anonymize_user(nil)
    end
  end
end
