defmodule KlassHero.Repo.Migrations.ScrubErrorTrackerContext do
  @moduledoc """
  Narrows `context` on the rows written before #1392 was fixed.

  `ErrorContextFilter` narrows context as it is written and was never applied to the rows that
  predate it, so 181 of the 182 production occurrences still carry user-submitted data verbatim —
  Oban job args and the params of the request or LiveView event that crashed.
  `ProcessInviteClaimWorker`'s args and the children form both carry a child's name, date of
  birth and medical conditions. The forward path is closed by the filter; this closes the
  history (#1406).

  Context-side twin of `20260818070001_scrub_error_tracker_reasons`, and the same three
  properties hold: it calls the filter rather than reimplementing it in SQL, the `Logger.info`
  count is the gate a human reads at deploy, and it is irreversible — the original values are
  the thing being destroyed, so `down/0` is a no-op.

  Only `error_tracker_occurrences` has a `context` column; the sibling scrub touched two tables
  because `reason` lives on both.

  `sanitize/1` is a fixpoint (see its moduledoc), so a row the filter has already narrowed
  survives this unchanged and re-running costs nothing but a read.

  This pins the migration to `KlassHero.Shared.ErrorContextFilter`. If that module is ever
  renamed or removed, replace this body with `:ok` — by then every environment has already run
  it.
  """

  use Ecto.Migration

  import Ecto.Query

  alias KlassHero.Shared.ErrorContextFilter

  require Logger

  @table "error_tracker_occurrences"

  def up do
    rows = repo().all(from(o in @table, select: {o.id, o.context}))

    narrowed =
      for {id, context} <- rows,
          is_map(context),
          scrubbed = ErrorContextFilter.sanitize(context),
          scrubbed != context do
        repo().update_all(from(o in @table, where: o.id == ^id), set: [context: scrubbed])
        id
      end

    Logger.info("#{@table}: narrowed #{length(narrowed)} of #{length(rows)} contexts")
  end

  def down, do: :ok
end
