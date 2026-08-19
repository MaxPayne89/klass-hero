defmodule KlassHero.Repo.Migrations.ScrubErrorTrackerReasons do
  @moduledoc """
  Narrows `reason` on the rows written before #1398 was fixed.

  Two production rows are known to embed user data — a `KeyError` rendering a message sent to
  parents plus a staff member's name, and a `MatchError` rendering an email address. The
  forward path is closed by `KlassHero.Shared.ErrorStore.Repo`; this closes the history.

  Irreversible: the original text is the thing being destroyed, so `down/0` is a no-op.

  This calls `ErrorReasonFilter.sanitize/1` rather than reimplementing it in SQL, which pins
  the migration to that module. If the module is ever renamed or removed, replace this body
  with `:ok` — by then every environment has already run it.
  """

  use Ecto.Migration

  import Ecto.Query

  alias KlassHero.Shared.ErrorReasonFilter

  require Logger

  @tables ~w(error_tracker_errors error_tracker_occurrences)

  def up do
    for table <- @tables, do: scrub(table)
  end

  def down, do: :ok

  defp scrub(table) do
    rows = repo().all(from(t in table, select: {t.id, t.reason}))

    narrowed =
      for {id, reason} <- rows,
          is_binary(reason),
          scrubbed = ErrorReasonFilter.sanitize(reason),
          scrubbed != reason do
        repo().update_all(from(t in table, where: t.id == ^id), set: [reason: scrubbed])
        id
      end

    Logger.info("#{table}: narrowed #{length(narrowed)} of #{length(rows)} reasons")
  end
end
