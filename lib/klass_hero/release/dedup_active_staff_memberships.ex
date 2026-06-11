defmodule KlassHero.Release.DedupActiveStaffMemberships do
  @moduledoc """
  Pre-index dedup for the active-staff-membership unique constraint (#969 review).

  Historically nothing stopped the same person from holding several active,
  linked staff rows at the SAME provider (e.g. repeated invites, both accepted).
  The `staff_members_active_provider_user_index` partial unique index closes
  the self-staffing double-submit race, but it cannot be created while such
  duplicates exist — so this deactivates (`active = false`, never deletes) all
  but the newest active row per (provider_id, user_id). Unlinked rows
  (user_id IS NULL) and memberships at different providers are untouched.

  Lives outside the migration so the transform is unit-testable (the #966
  pattern); the migration's `up/0` calls `run/1` before creating the index.
  Idempotent: re-running finds no duplicates and deactivates zero rows.
  """

  alias Ecto.Adapters.SQL

  require Logger

  @doc """
  Deactivates duplicate active linked rows, keeping the newest per
  (provider_id, user_id). Logs the count (HITL gate). Returns
  `{:ok, %{rows_deactivated: non_neg_integer}}`.
  """
  @spec run(Ecto.Repo.t()) :: {:ok, %{rows_deactivated: non_neg_integer()}}
  def run(repo) do
    repo.transaction(fn ->
      %{num_rows: rows_deactivated} =
        SQL.query!(repo, """
        UPDATE staff_members
        SET active = false
        WHERE id IN (
          SELECT id FROM (
            SELECT id,
                   row_number() OVER (
                     PARTITION BY provider_id, user_id
                     ORDER BY inserted_at DESC, id DESC
                   ) AS rn
            FROM staff_members
            WHERE active = true AND user_id IS NOT NULL
          ) ranked
          WHERE ranked.rn > 1
        )
        """)

      Logger.info(
        "[#969] dedup_active_staff_memberships: deactivated #{rows_deactivated} duplicate " <>
          "active staff rows ahead of the unique index"
      )

      %{rows_deactivated: rows_deactivated}
    end)
  end
end
