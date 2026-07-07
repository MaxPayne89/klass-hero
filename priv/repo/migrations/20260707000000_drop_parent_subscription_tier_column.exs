defmodule KlassHero.Repo.Migrations.DropParentSubscriptionTierColumn do
  use Ecto.Migration

  @moduledoc """
  Parent subscription tiers are removed (#925): every parent has full access
  (unlimited bookings, messaging enabled), so the tier column carries no
  information and is dropped. This completes the tier retirement started for
  providers in `20260607000001_drop_provider_subscription_tier_columns.exs`
  (ADR-0004); the parent half is executed here.

  Single column — there is no legacy duplicate on `users` for parents (the
  provider legacy column was already dropped).
  """

  def up do
    alter table(:parents) do
      remove :subscription_tier
    end
  end

  def down do
    alter table(:parents) do
      add :subscription_tier, :string, null: false, default: "explorer"
    end
  end
end
