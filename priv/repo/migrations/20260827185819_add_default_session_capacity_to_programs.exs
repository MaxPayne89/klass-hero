defmodule KlassHero.Repo.Migrations.AddDefaultSessionCapacityToPrograms do
  use Ecto.Migration

  # The capacity a schedule-generated Session inherits — "my room holds twelve",
  # stated once on the Program rather than re-typed on every date.
  #
  # Nullable with no default and no backfill: NULL means the provider named no
  # usual capacity, so generated Sessions stay uncapped exactly as they are today
  # and every existing Program keeps its current behaviour. A per-Session number
  # still wins where one was set, so manually created Sessions are unaffected.
  #
  # Not the Program's enrollment cap (`enrollment_policies.max_enrollment`), which
  # bounds bookings across the whole Program and is enforced at booking time. This
  # one is a template for generated rows and is enforced nowhere.
  def change do
    alter table(:programs) do
      add :default_session_capacity, :integer
    end

    create constraint(:programs, :default_session_capacity_positive,
             check: "default_session_capacity IS NULL OR default_session_capacity > 0"
           )
  end
end
