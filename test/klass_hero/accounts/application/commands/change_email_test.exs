defmodule KlassHero.Accounts.Application.Commands.ChangeEmailTest do
  @moduledoc """
  Integration tests for ChangeEmail use case.

  Verifies email-change orchestration: a valid confirmation token updates the
  user's email, and invalid tokens surface an :invalid_token error.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts
  alias KlassHero.Accounts.Adapters.Driven.Persistence.Repositories.UserRepository
  alias KlassHero.Accounts.Application.Commands.ChangeEmail
  alias KlassHero.Accounts.Domain.Models.User

  defp generate_email_change_token(user, new_email) do
    user_with_new_email = %{user | email: new_email}

    extract_user_token(fn url ->
      Accounts.deliver_user_update_email_instructions(
        user_with_new_email,
        user.email,
        url
      )
    end)
  end

  describe "execute/2 — success path" do
    test "returns User with updated email" do
      user = user_fixture()
      new_email = unique_user_email()
      token = generate_email_change_token(user, new_email)

      assert {:ok, %User{} = updated} = ChangeEmail.execute(user, token)
      assert updated.email == new_email
    end

    test "persists the new email to the database" do
      user = user_fixture()
      new_email = unique_user_email()
      token = generate_email_change_token(user, new_email)

      {:ok, _} = ChangeEmail.execute(user, token)

      assert {:ok, persisted} = UserRepository.get_by_id(user.id)
      assert persisted.email == new_email
    end
  end

  describe "execute/2 — token errors" do
    test "returns :invalid_token for a malformed token" do
      user = user_fixture()

      assert {:error, :invalid_token} = ChangeEmail.execute(user, "not-a-valid-token!")
    end

    test "returns :invalid_token for a nonexistent token" do
      user = user_fixture()
      fake_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      assert {:error, :invalid_token} = ChangeEmail.execute(user, fake_token)
    end
  end
end
