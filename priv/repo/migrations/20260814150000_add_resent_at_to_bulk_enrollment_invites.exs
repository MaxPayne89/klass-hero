defmodule KlassHero.Repo.Migrations.AddResentAtToBulkEnrollmentInvites do
  @moduledoc """
  When the provider last reopened this invite, so a compensation can tell whether it
  still describes the invite it was enqueued for.

  Nullable with no backfill on purpose: `nil` already means "never resent", which is
  true of every existing row, and any value we invented would be a resend that did not
  happen. `:utc_datetime_usec` to match `oban_jobs.inserted_at`, which is what it gets
  compared against — a second-precision column would round two events in the same
  second into a tie (#1339).
  """

  use Ecto.Migration

  def change do
    alter table(:bulk_enrollment_invites) do
      add :resent_at, :utc_datetime_usec
    end
  end
end
