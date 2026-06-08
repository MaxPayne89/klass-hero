defmodule KlassHero.Accounts.Types.UserRoleTest do
  use ExUnit.Case, async: true

  alias KlassHero.Accounts.Types.UserRole

  describe "valid_roles/0" do
    test "returns list of valid role atoms" do
      assert UserRole.valid_roles() == [:parent, :provider, :staff]
    end
  end

  describe "valid_role?/1" do
    test "returns true for :parent" do
      assert UserRole.valid_role?(:parent)
    end

    test "returns true for :provider" do
      assert UserRole.valid_role?(:provider)
    end

    test "returns false for invalid atom" do
      refute UserRole.valid_role?(:admin)
      refute UserRole.valid_role?(:user)
      refute UserRole.valid_role?(:invalid)
    end

    test "returns false for string" do
      refute UserRole.valid_role?("parent")
      refute UserRole.valid_role?("provider")
    end

    test "returns false for other types" do
      refute UserRole.valid_role?(nil)
      refute UserRole.valid_role?(123)
      refute UserRole.valid_role?(%{})
      refute UserRole.valid_role?([])
    end
  end

  describe "to_string/1" do
    test "converts :parent to string" do
      assert UserRole.to_string(:parent) == {:ok, "parent"}
    end

    test "converts :provider to string" do
      assert UserRole.to_string(:provider) == {:ok, "provider"}
    end

    test "returns error for invalid atom" do
      assert UserRole.to_string(:admin) == {:error, :invalid_role}
      assert UserRole.to_string(:invalid) == {:error, :invalid_role}
    end

    test "returns error for string" do
      assert UserRole.to_string("parent") == {:error, :invalid_role}
    end

    test "returns error for other types" do
      assert UserRole.to_string(nil) == {:error, :invalid_role}
      assert UserRole.to_string(123) == {:error, :invalid_role}
    end
  end

  describe "from_string/1" do
    test "converts 'parent' string to atom" do
      assert UserRole.from_string("parent") == {:ok, :parent}
    end

    test "converts 'provider' string to atom" do
      assert UserRole.from_string("provider") == {:ok, :provider}
    end

    test "returns error for invalid string" do
      assert UserRole.from_string("admin") == {:error, :invalid_role}
      assert UserRole.from_string("user") == {:error, :invalid_role}
      assert UserRole.from_string("invalid") == {:error, :invalid_role}
    end

    test "returns error for empty string" do
      assert UserRole.from_string("") == {:error, :invalid_role}
    end

    test "returns error for atom" do
      assert UserRole.from_string(:parent) == {:error, :invalid_role}
    end

    test "returns error for other types" do
      assert UserRole.from_string(nil) == {:error, :invalid_role}
      assert UserRole.from_string(123) == {:error, :invalid_role}
      assert UserRole.from_string(%{}) == {:error, :invalid_role}
    end

    test "prevents atom pollution by using to_existing_atom" do
      # This should not create a new atom
      assert UserRole.from_string("nonexistent_role_xyz") == {:error, :invalid_role}
      # Verify the atom wasn't created (this would raise if it was created)
      assert_raise ArgumentError, fn ->
        String.to_existing_atom("nonexistent_role_xyz")
      end
    end
  end

  describe "permissions/1" do
    test "returns parent permissions" do
      permissions = UserRole.permissions(:parent)

      assert :view_programs in permissions
      assert :enroll_children in permissions
      assert :view_child_progress in permissions
      assert :manage_family_profile in permissions
      assert :submit_reviews in permissions
      assert length(permissions) == 5
    end

    test "returns provider permissions" do
      permissions = UserRole.permissions(:provider)

      assert :manage_programs in permissions
      assert :view_enrollments in permissions
      assert :manage_schedule in permissions
      assert :view_analytics in permissions
      assert :respond_to_reviews in permissions
      assert length(permissions) == 5
    end

    test "returns empty list for invalid role atom" do
      assert UserRole.permissions(:admin) == []
      assert UserRole.permissions(:invalid) == []
    end

    test "returns empty list for string" do
      assert UserRole.permissions("parent") == []
    end

    test "returns empty list for other types" do
      assert UserRole.permissions(nil) == []
      assert UserRole.permissions(123) == []
      assert UserRole.permissions(%{}) == []
    end
  end
end
