defmodule KlassHero.Repo.Migrations.RenameStaffProviderRoleToStaffTest do
  @moduledoc """
  Characterization test for the data migration that renames the legacy
  `"staff_provider"` role string to `"staff"` inside `users.intended_roles`
  (ADR-0005). The migration ships as inline SQL (repo convention); this test
  pins the `array_replace` transformation's semantics so a typo in the value,
  column, or replacement order is caught.
  """
  use KlassHero.DataCase, async: true

  # Must stay byte-identical to the UPDATE the migration runs.
  @rename_sql """
  UPDATE users
  SET intended_roles = array_replace(intended_roles, 'staff_provider', 'staff')
  WHERE 'staff_provider' = ANY(intended_roles)
  """

  defp insert_user_with_roles(roles) do
    %{rows: [[id]]} =
      Repo.query!(
        """
        INSERT INTO users (id, email, name, intended_roles, is_admin, inserted_at, updated_at)
        VALUES (gen_random_uuid(), $1, 'Test User', $2::text[], false, now(), now())
        RETURNING id
        """,
        ["#{System.unique_integer([:positive])}@example.com", roles]
      )

    id
  end

  defp roles_of(id) do
    %{rows: [[roles]]} =
      Repo.query!("SELECT intended_roles FROM users WHERE id = $1", [id])

    roles
  end

  test "renames staff_provider to staff while preserving sibling roles" do
    dual = insert_user_with_roles(["staff_provider", "provider"])
    staff_only = insert_user_with_roles(["staff_provider"])

    Repo.query!(@rename_sql)

    assert roles_of(dual) == ["staff", "provider"]
    assert roles_of(staff_only) == ["staff"]
  end

  test "leaves rows without staff_provider untouched" do
    parent = insert_user_with_roles(["parent"])
    provider = insert_user_with_roles(["provider"])

    Repo.query!(@rename_sql)

    assert roles_of(parent) == ["parent"]
    assert roles_of(provider) == ["provider"]
  end
end
