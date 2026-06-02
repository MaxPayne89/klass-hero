defmodule KlassHero.Accounts.Application.Commands.RegisterUserTest do
  @moduledoc """
  Integration tests for RegisterUser use case.

  Verifies user creation orchestration: successful registration returns a
  User, validation failures surface the changeset, and duplicate emails are
  rejected.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts.Application.Commands.RegisterUser
  # Auth uses phx.gen.auth: KlassHero.Accounts.User (the Ecto schema) is the
  # canonical user type these commands return — not a separate domain model.
  alias KlassHero.Accounts.User

  describe "execute/1 — success path" do
    test "returns domain User on valid attributes" do
      attrs = valid_user_attributes()

      assert {:ok, %User{} = user} = RegisterUser.execute(attrs)
      assert user.email == attrs.email
      assert user.name == attrs.name
    end
  end

  describe "execute/1 — validation failures" do
    test "returns changeset error for empty attributes" do
      assert {:error, %Ecto.Changeset{}} = RegisterUser.execute(%{})
    end

    test "returns changeset error for missing email" do
      assert {:error, %Ecto.Changeset{} = cs} =
               RegisterUser.execute(%{name: "Alice", intended_roles: [:parent]})

      assert {:email, _} = hd(cs.errors)
    end

    test "returns changeset error for duplicate email" do
      attrs = valid_user_attributes()
      {:ok, _} = RegisterUser.execute(attrs)

      assert {:error, %Ecto.Changeset{}} = RegisterUser.execute(attrs)
    end
  end
end
