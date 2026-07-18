defmodule KlassHero.Repo.Migrations.AddSessionDateStatusIndexToProgramSessions do
  use Ecto.Migration

  @moduledoc """
  Admin sessions dashboard (`Participation.list_admin_sessions/1`) defaults to
  `session_date == today` and optionally filters `status`. The only existing
  index — `unique_index(:program_sessions, [:program_id, :session_date, :start_time])`
  — leads with `program_id`, so a `session_date`-led lookup can't use it and
  Postgres seq-scans the table on every dashboard load. Lead with `session_date`
  (also serves `list_sessions_today/1`), trail with `status` to cover the filter.
  """

  def change do
    create index(:program_sessions, [:session_date, :status])
  end
end
