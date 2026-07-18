defmodule KlassHero.Repo.Migrations.AddStatusEnrolledAtIndexToEnrollments do
  use Ecto.Migration

  @moduledoc """
  The admin bookings screen filters enrollments by `status` and sorts by
  `enrolled_at desc`. No existing index leads with `status`, so Postgres walks
  the `enrolled_at` index discarding non-matching rows. Lead with `status`,
  trail with `enrolled_at` to serve filter + sort together.
  """

  def change do
    create index(:enrollments, [:status, :enrolled_at])
  end
end
