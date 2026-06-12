defmodule KlassHero.Repo.Migrations.RenameStaffProviderRoleToStaff do
  @moduledoc """
  Renames the legacy `"staff_provider"` role to `"staff"` inside the
  `users.intended_roles` text[] column (ADR-0005: Staff and Provider are
  independent personas).

  Must run before the renamed code serves rows: once `:staff_provider` leaves
  `UserRole.valid_roles/0`, `UserRoles.load/1` fails for any row still holding
  the legacy string. Pure data change — no schema flush needed.

  Deploy note: this rewrites `users.intended_roles` only, NOT frozen Oban job
  args. A `user_registered` integration event enqueued by the old code carries
  `"staff_provider"` in its payload; after deploy, `ProviderEventHandler`'s guard
  (`"staff" not in intended_roles`) no longer recognises it as staff and may
  create a spurious provider profile for a staff user. Bounded to the deploy
  window. Either drain the staff-registration `user_registered` queue before
  deploying, or accept the window — the whole path is removed by #965.
  """
  use Ecto.Migration

  def up do
    execute("""
    UPDATE users
    SET intended_roles = array_replace(intended_roles, 'staff_provider', 'staff')
    WHERE 'staff_provider' = ANY(intended_roles)
    """)
  end

  def down do
    execute("""
    UPDATE users
    SET intended_roles = array_replace(intended_roles, 'staff', 'staff_provider')
    WHERE 'staff' = ANY(intended_roles)
    """)
  end
end
