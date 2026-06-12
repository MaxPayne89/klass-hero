defmodule KlassHero.Accounts.Adapters.Driven.Persistence.Schemas.UserRemoveRoleTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Accounts.User

  describe "remove_role_changeset/2" do
    test "removes the role, preserving the others" do
      changeset = User.remove_role_changeset(%User{intended_roles: [:provider, :staff]}, :staff)

      assert changeset.valid?
      assert get_change(changeset, :intended_roles) == [:provider]
    end

    test "is idempotent — removing a role not present is a no-op" do
      changeset = User.remove_role_changeset(%User{intended_roles: [:provider]}, :staff)

      assert get_field(changeset, :intended_roles) == [:provider]
    end

    test "can empty the list when the removed role was the only one" do
      changeset = User.remove_role_changeset(%User{intended_roles: [:staff]}, :staff)

      assert get_change(changeset, :intended_roles) == []
    end

    test "treats nil intended_roles as empty" do
      changeset = User.remove_role_changeset(%User{intended_roles: nil}, :staff)

      assert get_field(changeset, :intended_roles) == []
    end
  end
end
