defmodule KlassHero.Release.CleanupLegacyStaffInviteProfiles do
  @moduledoc """
  One-off blanket cleanup of the legacy staff→provider conflation (ADR-0005, #966).

  Before #965, accepting a staff invitation auto-created a draft `ProviderProfile`
  (`originated_from = "staff_invite"`) and forced `:provider` into the user's roles.
  This removes those artifacts: every staff-invite profile is deleted and `:provider`
  is stripped from the owning users (they revert to staff-only; they may deliberately
  re-upgrade later — #968). Other roles (`:parent`, `:staff`) are untouched.

  Lives outside the migration so the exact transform is unit-testable; the migration's
  `up/0` calls `run/1`. Pure SQL against the `providers`/`users` tables — no context
  schema dependencies, so it stays Boundary-clean.

  Idempotent: re-running finds no staff-invite rows and returns zero counts.
  """

  alias Ecto.Adapters.SQL

  require Logger

  @legacy_origin "staff_invite"

  @doc """
  Strips `:provider` from staff-invite users, then deletes the staff-invite profiles.

  Logs the affected counts before the destructive step (HITL gate). Runs in a single
  transaction so a failure leaves the data untouched. Returns
  `{:ok, %{profiles_deleted: non_neg_integer, users_updated: non_neg_integer}}`.
  """
  @spec run(Ecto.Repo.t()) :: {:ok, %{profiles_deleted: non_neg_integer(), users_updated: non_neg_integer()}}
  def run(repo) do
    repo.transaction(fn ->
      %{rows: [[profile_count, user_count]]} =
        SQL.query!(
          repo,
          "SELECT count(*), count(DISTINCT identity_id) FROM providers WHERE originated_from = $1",
          [@legacy_origin]
        )

      Logger.info(
        "[#966] cleanup_legacy_staff_invite_profiles: deleting #{profile_count} staff-invite " <>
          "provider profiles affecting #{user_count} users"
      )

      # Strip :provider BEFORE deleting the profiles — the subquery needs the rows to
      # still exist to resolve which users to update.
      %{num_rows: users_updated} =
        SQL.query!(
          repo,
          """
          UPDATE users
          SET intended_roles = array_remove(intended_roles, 'provider')
          WHERE id IN (SELECT identity_id FROM providers WHERE originated_from = $1)
            AND 'provider' = ANY(intended_roles)
          """,
          [@legacy_origin]
        )

      %{num_rows: profiles_deleted} =
        SQL.query!(repo, "DELETE FROM providers WHERE originated_from = $1", [@legacy_origin])

      %{profiles_deleted: profiles_deleted, users_updated: users_updated}
    end)
  end
end
