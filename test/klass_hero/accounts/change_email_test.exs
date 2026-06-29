defmodule KlassHero.Accounts.ChangeEmailTest do
  @moduledoc """
  Integration tests for `Accounts.update_user_email/2`.

  Verifies email-change orchestration: a valid confirmation token updates the
  user's email, and invalid tokens surface an :invalid_token error.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts
  # Auth uses phx.gen.auth: KlassHero.Accounts.User (the Ecto schema) is the
  # canonical user type the context returns — not a separate domain model.
  alias KlassHero.Accounts.User

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

  describe "update_user_email/2 — success path" do
    test "returns User with updated email" do
      user = user_fixture()
      new_email = unique_user_email()
      token = generate_email_change_token(user, new_email)

      assert {:ok, %User{} = updated} = Accounts.update_user_email(user, token)
      assert updated.email == new_email
    end

    test "persists the new email to the database" do
      user = user_fixture()
      new_email = unique_user_email()
      token = generate_email_change_token(user, new_email)

      {:ok, _} = Accounts.update_user_email(user, token)

      persisted = Accounts.get_user!(user.id)
      assert persisted.email == new_email
    end
  end

  describe "update_user_email/2 — token errors" do
    test "returns :invalid_token for a malformed token" do
      user = user_fixture()

      assert {:error, :invalid_token} = Accounts.update_user_email(user, "not-a-valid-token!")
    end

    test "returns :invalid_token for a nonexistent token" do
      user = user_fixture()
      fake_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      assert {:error, :invalid_token} = Accounts.update_user_email(user, fake_token)
    end
  end
end
