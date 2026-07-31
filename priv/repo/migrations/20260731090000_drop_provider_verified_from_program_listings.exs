defmodule KlassHero.Repo.Migrations.DropProviderVerifiedFromProgramListings do
  @moduledoc """
  Drops `program_listings.provider_verified` (#1195).

  The column was maintained by the `ProgramListings` projection from Provider's
  `provider_verified`/`provider_unverified` integration events, and read by
  nothing — the program card that would have shown it was never wired up. Program
  cards now read provider trust state directly through `Provider.get_trust_states/1`,
  so Program Catalog no longer denormalises Provider state at all.

  Reversible for schema, not for data: `down/0` re-adds the column with its
  original default, but the projection that populated it is gone, so a rollback
  yields `false` everywhere until the events and handlers are restored too.
  """
  use Ecto.Migration

  def up do
    alter table(:program_listings) do
      remove :provider_verified
    end
  end

  def down do
    alter table(:program_listings) do
      add :provider_verified, :boolean, default: false, null: false
    end
  end
end
