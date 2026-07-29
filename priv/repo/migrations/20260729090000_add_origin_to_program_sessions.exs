defmodule KlassHero.Repo.Migrations.AddOriginToProgramSessions do
  @moduledoc """
  Distinguishes sessions derived from a program's recurring schedule from
  one-offs a provider entered by hand.

  Only `generated` sessions are swept when a schedule changes, so a deliberate
  one-off survives an edit. Existing rows take the `manual` default, which means
  no session that exists today can ever be cancelled by that sweep.

  `max_capacity` is relaxed to nullable in the same change: it has been
  `null: false` with no default since the table was created, and a program
  carries no capacity to derive one from, so generated rows would have nothing
  to put there. It also fixes an existing hole — the manual session form omits
  the field entirely when a provider leaves it blank.
  """

  use Ecto.Migration

  def change do
    alter table(:program_sessions) do
      # Constant default: metadata-only on PG 11+, so no table rewrite.
      add :origin, :string, null: false, default: "manual"
      modify :max_capacity, :integer, null: true, from: {:integer, null: false}
    end

    create index(:program_sessions, [:program_id, :origin, :status])
  end
end
