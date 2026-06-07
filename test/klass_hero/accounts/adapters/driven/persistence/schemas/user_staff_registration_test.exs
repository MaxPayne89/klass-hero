defmodule KlassHero.Accounts.Adapters.Driven.Persistence.Schemas.UserStaffRegistrationTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Accounts.User

  describe "staff_registration_changeset/3" do
    test "valid with name, email, and password" do
      changeset =
        User.staff_registration_changeset(%User{}, %{
          name: "Jane Doe",
          email: "jane@example.com",
          password: "valid_password_123"
        })

      assert changeset.valid?
      assert get_change(changeset, :intended_roles) == [:staff_provider, :provider]
    end

    test "locks intended_roles to [:staff_provider, :provider]" do
      changeset =
        User.staff_registration_changeset(%User{}, %{
          name: "Jane Doe",
          email: "jane@example.com",
          password: "valid_password_123",
          intended_roles: [:parent]
        })

      assert get_change(changeset, :intended_roles) == [:staff_provider, :provider]
    end

    test "is valid with just name and email" do
      changeset =
        User.staff_registration_changeset(%User{}, %{
          name: "Jane Doe",
          email: "jane@example.com",
          password: "valid_password_123"
        })

      assert changeset.valid?
    end

    test "requires name" do
      changeset =
        User.staff_registration_changeset(%User{}, %{
          email: "jane@example.com",
          password: "valid_password_123"
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires email" do
      changeset =
        User.staff_registration_changeset(%User{}, %{
          name: "Jane Doe",
          password: "valid_password_123"
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).email
    end

    test "validates email format" do
      changeset =
        User.staff_registration_changeset(%User{}, %{
          name: "Jane Doe",
          email: "invalid",
          password: "valid_password_123"
        })

      refute changeset.valid?
    end

    test "requires password" do
      changeset =
        User.staff_registration_changeset(%User{}, %{
          name: "Jane Doe",
          email: "jane@example.com"
        })

      refute changeset.valid?
    end
  end

  describe "staff_registration_changeset/3 always includes :provider role" do
    test "sets [:staff_provider, :provider] by default" do
      attrs = %{"name" => "Test", "email" => "test@example.com", "password" => "long_password123"}

      changeset = User.staff_registration_changeset(%User{}, attrs, hash_password: false)
      assert Ecto.Changeset.get_field(changeset, :intended_roles) == [:staff_provider, :provider]
    end

    test "ignores also_provider param — always includes :provider" do
      attrs = %{
        "name" => "Test",
        "email" => "test@example.com",
        "password" => "long_password123",
        "also_provider" => "false"
      }

      changeset = User.staff_registration_changeset(%User{}, attrs, hash_password: false)
      assert Ecto.Changeset.get_field(changeset, :intended_roles) == [:staff_provider, :provider]
    end
  end
end
