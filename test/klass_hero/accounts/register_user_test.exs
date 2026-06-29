defmodule KlassHero.Accounts.RegisterUserTest do
  @moduledoc """
  Integration tests for `Accounts.register_user/1`.

  Verifies user creation orchestration: successful registration returns a
  User, validation failures surface the changeset, and duplicate emails are
  rejected.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts
  # Auth uses phx.gen.auth: KlassHero.Accounts.User (the Ecto schema) is the
  # canonical user type the context returns — not a separate domain model.
  alias KlassHero.Accounts.User

  describe "register_user/1 — success path" do
    test "returns the User on valid attributes" do
      attrs = valid_user_attributes()

      assert {:ok, %User{} = user} = Accounts.register_user(attrs)
      assert user.email == attrs.email
      assert user.name == attrs.name
    end
  end

  describe "register_user/1 — validation failures" do
    test "returns changeset error for empty attributes" do
      assert {:error, %Ecto.Changeset{}} = Accounts.register_user(%{})
    end

    test "returns changeset error for missing email" do
      assert {:error, %Ecto.Changeset{} = cs} =
               Accounts.register_user(%{name: "Alice", intended_roles: [:parent]})

      assert {:email, _} = hd(cs.errors)
    end

    test "returns changeset error for duplicate email" do
      attrs = valid_user_attributes()
      {:ok, _} = Accounts.register_user(attrs)

      assert {:error, %Ecto.Changeset{}} = Accounts.register_user(attrs)
    end
  end
end
