defmodule KlassHero.Shared.SubscriptionTiersTest do
  use ExUnit.Case, async: true

  alias KlassHero.Shared.SubscriptionTiers

  describe "parent tiers" do
    test "parent_tiers/0 returns the two parent tier atoms" do
      assert SubscriptionTiers.parent_tiers() == [:explorer, :active]
    end

    test "valid_parent_tier?/1 accepts only parent tier atoms" do
      assert SubscriptionTiers.valid_parent_tier?(:explorer)
      assert SubscriptionTiers.valid_parent_tier?(:active)

      refute SubscriptionTiers.valid_parent_tier?(:starter)
      refute SubscriptionTiers.valid_parent_tier?("explorer")
      refute SubscriptionTiers.valid_parent_tier?(nil)
    end

    test "default_parent_tier/0 returns :explorer" do
      assert SubscriptionTiers.default_parent_tier() == :explorer
    end
  end
end
