defmodule KlassHero.Release.BackfillDirectConversationPrincipals do
  @moduledoc """
  Pre-index backfill for `conversations.principal_a_id/principal_b_id` (#747).

  A `:direct` thread used to be identified by "the provider plus one participant",
  which cannot express a thread between two provider-side people and hands an owner
  their staff member's thread with a parent (#1521). The principal pair makes "the
  thread between these two" a stored fact, separate from membership — seated staff
  stay participants without becoming principals.

  Every row predating this migration is `{provider owner, one parent}` plus seated
  staff: all three creators resolved the provider side to the owner
  (`Provider.get_identity_id_for_provider/1`, or `provider.identity_id` via
  `build_compose_target/3`), and staff only ever entered through `AddAssignedStaff`
  or `StaffAssignmentHandler`, never as a creation-time party.

  ## Why the counterparty is derived from parenthood, not from "not staff"

  Subtracting the *current* staff roster would re-derive history from live state —
  the exact shape behind #1237/#1292/#1320, where the roster drifted and the
  derived answer went stale. A `parents` row is a stable identity fact, so it is
  the side used here.

  `joined_at` cannot order the principals and is deliberately unused:
  `Messaging.add_participant/1` reads `DateTime.utc_now()` once per call and stores
  `:utc_datetime` (whole seconds), the two principals are inserted
  initiator-first rather than owner-first, and `StaffAssignmentHandler` seats staff
  arbitrarily later.

  Lives outside the migration so the transform is unit-testable (the #966 pattern).
  Idempotent: it only considers rows whose principals are still NULL.

  ## Why this reads Provider's and Family's tables directly

  ADR-0015 says a context reaching for another's data calls its root facade under
  an `acl_span`. This joins `providers` and `parents` in raw SQL instead, and that
  is deliberate:

    * It runs inside a migration's `up/0`, against whatever schema exists at that
      point in history. A facade compiled against *today's* schema is the wrong
      shape to point at a mid-migration database, which is the coupling
      `KlassHero.Release.DedupActiveStaffMemberships` already avoids the same way.
    * It is a one-shot historical backfill over a bounded set — production was
      verified clean first (26 of 26 rows resolvable, 0 archived, 0 duplicate
      pairs) — not a runtime read path anything queries again.
    * A facade round-trip per row would turn one statement into N.

  Note that `mix lint_acl_boundary` cannot see this hop: it matches Ecto's
  schemaless `in "table"` binding, not a table name inside a SQL heredoc. So the
  exemption is load-bearing rather than merely tolerated, and this comment is the
  only thing recording it.

  Do not copy this into a context module. It is scoped to `lib/klass_hero/release/`
  migration scripts — see `.claude/rules/domain-architecture.md`.

  ## Unresolved rows raise

  A row that does not resolve to exactly one parent participant is not guessed at.
  Production was verified clean (26 of 26 resolvable, 0 archived) before this was
  written, so a raise here means something genuinely unexpected exists and a human
  should look before the pair index is created on top of it.
  """

  alias Ecto.Adapters.SQL

  require Logger

  defmodule UnresolvedError do
    defexception [:message]
  end

  @doc """
  Fills the principal pair on `:direct` rows that lack one.

  Returns `{:ok, %{rows_filled: non_neg_integer}}`. Raises `UnresolvedError` if any
  `:direct` row is left without principals.
  """
  @spec run(Ecto.Repo.t()) :: {:ok, %{rows_filled: non_neg_integer()}}
  def run(repo) do
    repo.transaction(fn ->
      %{num_rows: rows_filled} = fill_resolvable(repo)
      raise_on_unresolved(repo)

      Logger.info("[#747] backfill_direct_conversation_principals: filled #{rows_filled} rows")

      %{rows_filled: rows_filled}
    end)
  end

  # array_agg + an explicit length check rather than a LATERAL join: a join would
  # silently pick a row when a conversation somehow holds two parents, which is
  # precisely the case that must surface instead.
  defp fill_resolvable(repo) do
    SQL.query!(repo, """
    WITH resolved AS (
      SELECT c.id AS conversation_id,
             pr.identity_id AS owner_id,
             array_agg(cp.user_id) FILTER (
               WHERE pa.identity_id IS NOT NULL AND cp.user_id <> pr.identity_id
             ) AS parent_ids
      FROM conversations c
      JOIN providers pr ON pr.id = c.provider_id
      JOIN conversation_participants cp
        ON cp.conversation_id = c.id AND cp.left_at IS NULL
      LEFT JOIN parents pa ON pa.identity_id = cp.user_id
      WHERE c.type = 'direct' AND c.principal_a_id IS NULL
      GROUP BY c.id, pr.identity_id
    )
    UPDATE conversations c
    SET principal_a_id = LEAST(r.owner_id, r.parent_ids[1]),
        principal_b_id = GREATEST(r.owner_id, r.parent_ids[1])
    FROM resolved r
    WHERE c.id = r.conversation_id
      AND array_length(r.parent_ids, 1) = 1
    """)
  end

  defp raise_on_unresolved(repo) do
    ids =
      SQL.query!(repo, """
      SELECT id FROM conversations WHERE type = 'direct' AND principal_a_id IS NULL
      """).rows
      |> List.flatten()
      |> Enum.map(&Ecto.UUID.cast!/1)

    if ids != [] do
      raise UnresolvedError,
        message:
          "[#747] #{length(ids)} direct conversation(s) did not resolve to exactly one " <>
            "parent participant and were left without principals: #{inspect(ids)}"
    end
  end
end
