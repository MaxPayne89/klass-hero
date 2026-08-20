defmodule KlassHero.Accounts.UserAddRoleTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Accounts.User

  describe "add_role_changeset/2" do
    test "appends the role, preserving existing roles" do
      changeset = User.add_role_changeset(%User{intended_roles: [:parent]}, :staff)

      assert changeset.valid?
      assert get_change(changeset, :intended_roles) == [:parent, :staff]
    end

    test "is idempotent — adding a role already present is a no-op" do
      changeset = User.add_role_changeset(%User{intended_roles: [:staff]}, :staff)

      assert get_field(changeset, :intended_roles) == [:staff]
    end

    test "preserves :provider when adding :staff (dual persona)" do
      changeset = User.add_role_changeset(%User{intended_roles: [:provider]}, :staff)

      assert get_field(changeset, :intended_roles) == [:provider, :staff]
    end

    test "treats nil intended_roles as empty" do
      changeset = User.add_role_changeset(%User{intended_roles: nil}, :staff)

      assert get_change(changeset, :intended_roles) == [:staff]
    end

    test "rejects an unknown role" do
      changeset = User.add_role_changeset(%User{intended_roles: [:parent]}, :wizard)

      refute changeset.valid?
    end
  end
end
