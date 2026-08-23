defmodule KlassHero.Repo.Migrations.AddSubtitleToProgramListings do
  use Ecto.Migration

  # :text, never a capped varchar. A read table has no changeset — the projection
  # is its only writer — so a width cap here cannot reject an over-long value. It
  # can only raise Postgres 22001 inside EventDeliveryWorker, burn all ten Oban
  # attempts and discard the event, losing every field of that update, not just
  # this one (#1376). The cap lives on `programs`, where a changeset turns it
  # into a validation error the provider sees.
  def change do
    alter table(:program_listings) do
      add :subtitle, :text
    end
  end
end
