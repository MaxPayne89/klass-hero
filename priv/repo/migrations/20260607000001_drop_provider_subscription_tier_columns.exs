defmodule KlassHero.Repo.Migrations.DropProviderSubscriptionTierColumns do
  use Ecto.Migration

  @moduledoc """
  Provider subscription tiers are removed (ADR-0004): every provider has
  full access, with a success-based fee planned as the replacement. The
  old tier values carry no information the future fee model needs, so
  both storage columns are dropped:

  - `providers.subscription_tier` — the active column
  - `users.provider_subscription_tier` — legacy column superseded by the
    providers table, already unread before this migration
  """

  def up do
    alter table(:providers) do
      remove :subscription_tier
    end

    alter table(:users) do
      remove :provider_subscription_tier
    end
  end

  def down do
    alter table(:providers) do
      add :subscription_tier, :string, default: "starter"
    end

    alter table(:users) do
      add :provider_subscription_tier, :string
    end
  end
end
