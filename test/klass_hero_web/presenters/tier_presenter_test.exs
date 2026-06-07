defmodule KlassHeroWeb.Presenters.TierPresenterTest do
  use ExUnit.Case, async: true

  alias KlassHeroWeb.Presenters.TierPresenter

  describe "tier_label/1" do
    test "returns human-readable name for each provider tier" do
      assert TierPresenter.tier_label(:starter) == "Starter"
      assert TierPresenter.tier_label(:professional) == "Professional"
      assert TierPresenter.tier_label(:business_plus) == "Business Plus"
    end

    test "raises FunctionClauseError for unknown tier" do
      # apply/3 defeats the compile-time type tracker, which otherwise
      # warns that :unknown can never match the function's clauses
      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(TierPresenter, :tier_label, [:unknown])
      end
    end
  end

  describe "tier_plan_label/1" do
    test "appends Plan suffix to tier name" do
      assert TierPresenter.tier_plan_label(:starter) == "Starter Plan"
      assert TierPresenter.tier_plan_label(:professional) == "Professional Plan"
      assert TierPresenter.tier_plan_label(:business_plus) == "Business Plus Plan"
    end
  end

  describe "tier_features/1" do
    test "starter features include program limit, commission, media, and team seat" do
      features = TierPresenter.tier_features(:starter)
      assert is_list(features)
      assert Enum.any?(features, &(&1 =~ "2 programs"))
      assert Enum.any?(features, &(&1 =~ "18% commission"))
      assert Enum.any?(features, &(&1 =~ "Avatar"))
      assert Enum.any?(features, &(&1 =~ "team seat"))
    end

    test "professional features include messaging" do
      features = TierPresenter.tier_features(:professional)
      assert "Direct messaging" in features
    end

    test "business_plus features include promotional content" do
      features = TierPresenter.tier_features(:business_plus)
      assert "Promotional content" in features
    end

    test "business_plus features include unlimited team seats" do
      features = TierPresenter.tier_features(:business_plus)
      assert Enum.any?(features, &(&1 =~ "Unlimited team seats"))
    end
  end

  describe "subscription_tiers/0" do
    test "returns all three provider tiers with required keys" do
      tiers = TierPresenter.subscription_tiers()
      assert length(tiers) == 3

      keys = Enum.map(tiers, & &1.key)
      assert keys == [:starter, :professional, :business_plus]

      for tier <- tiers do
        assert Map.has_key?(tier, :title)
        assert Map.has_key?(tier, :subtitle)
        assert Map.has_key?(tier, :price)
        assert Map.has_key?(tier, :period)
        assert Map.has_key?(tier, :features)
        assert is_list(tier.features)
      end
    end
  end
end
