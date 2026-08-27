defmodule KlassHero.Repo.Migrations.AddCapacitySourceToProgramSessions do
  @moduledoc """
  Separates a Session Capacity a Program dictates from one a human chose.

  Generated sessions inherit their Program's `default_session_capacity`, and that
  inheritance is maintained — changing the default realigns every upcoming
  generated session, so a provider who raises their capacity sees it take effect
  rather than watching old dates keep a stale number.

  That sweep must not overrule a deliberate choice. A provider can open one
  generated date and give it its own capacity (`ParticipationLive` ->
  `Participation.update_session/3`), and that number has to outlive every later
  Program write. `origin` cannot express this: it says where the *session* came
  from, not where its *capacity* came from, and both kinds of capacity live on
  rows with `origin: :generated`.

  Existing rows take `inherited`, which is the truth for all of them: no capacity
  has ever been set on a generated session — they are uncapped today — and manual
  sessions are excluded from the sweep by `origin` regardless of this column.
  """

  use Ecto.Migration

  def change do
    alter table(:program_sessions) do
      # Constant default: metadata-only on PG 11+, so no table rewrite.
      add :capacity_source, :string, null: false, default: "inherited"
    end
  end
end
