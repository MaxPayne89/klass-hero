defmodule KlassHero.Repo.Migrations.CleanupLegacyStaffInviteProfiles do
  @moduledoc """
  Blanket cleanup of the legacy staff→provider conflation (ADR-0005, #966).

  Deletes every `ProviderProfile` with `originated_from = "staff_invite"` and strips
  `:provider` from the owning users (they revert to staff-only; #968 lets them re-upgrade
  deliberately). The count logging that precedes the destructive step is the HITL gate.

  Runs after `20260608000001_rename_staff_provider_role_to_staff` — both touch
  `users.intended_roles`. The whole transform runs in one transaction, so a failure
  leaves the data untouched. Idempotent: a re-run finds no staff-invite rows.

  Pure SQL against `providers`/`users` — the `originated_from` column still exists at
  this point in the migration sequence (it's dropped later by
  `20260612000000_drop_originated_from_from_providers`).

  Irreversible: deleted profiles cannot be reconstructed, so `down/0` is a no-op. Affected
  users keep `:staff` and re-acquire provider-hood only by deliberate registration.
  """
  use Ecto.Migration

  alias Ecto.Adapters.SQL

  require Logger

  @legacy_origin "staff_invite"

  def up do
    repo().transaction(fn ->
      %{rows: [[profile_count, user_count]]} =
        SQL.query!(
          repo(),
          "SELECT count(*), count(DISTINCT identity_id) FROM providers WHERE originated_from = $1",
          [@legacy_origin]
        )

      Logger.info(
        "[#966] cleanup_legacy_staff_invite_profiles: deleting #{profile_count} staff-invite " <>
          "provider profiles affecting #{user_count} users"
      )

      # Strip :provider BEFORE deleting the profiles — the subquery needs the rows to
      # still exist to resolve which users to update.
      SQL.query!(
        repo(),
        """
        UPDATE users
        SET intended_roles = array_remove(intended_roles, 'provider')
        WHERE id IN (SELECT identity_id FROM providers WHERE originated_from = $1)
          AND 'provider' = ANY(intended_roles)
        """,
        [@legacy_origin]
      )

      SQL.query!(repo(), "DELETE FROM providers WHERE originated_from = $1", [@legacy_origin])
    end)
  end

  def down do
    :ok
  end
end
