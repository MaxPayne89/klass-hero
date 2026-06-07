defmodule KlassHero.Shared.EntitlementsTest do
  use ExUnit.Case, async: false

  alias KlassHero.Accounts.Scope
  alias KlassHero.Family.Domain.Models.ParentProfile
  alias KlassHero.Provider.Domain.Models.ProviderProfile
  alias KlassHero.Shared.Entitlements

  # Helper to create a parent with a specific tier
  defp parent_with_tier(tier) do
    %ParentProfile{
      id: "parent-123",
      identity_id: "identity-123",
      subscription_tier: tier
    }
  end

  # Provider tiers removed (ADR-0004): providers carry no tier
  defp provider_fixture do
    %ProviderProfile{
      id: "provider-123",
      identity_id: "identity-123",
      business_name: "Test Business"
    }
  end

  describe "parent entitlements - can_create_booking?/2" do
    test "explorer tier can book up to 2/month" do
      parent = parent_with_tier(:explorer)

      assert Entitlements.can_create_booking?(parent, 0)
      assert Entitlements.can_create_booking?(parent, 1)
      refute Entitlements.can_create_booking?(parent, 2)
      refute Entitlements.can_create_booking?(parent, 10)
    end

    test "active tier has unlimited bookings" do
      parent = parent_with_tier(:active)

      assert Entitlements.can_create_booking?(parent, 0)
      assert Entitlements.can_create_booking?(parent, 100)
      assert Entitlements.can_create_booking?(parent, 1000)
    end
  end

  describe "parent entitlements - ensure_booking_capacity/2" do
    test "returns {:ok, parent} when explorer is within cap" do
      parent = parent_with_tier(:explorer)

      assert {:ok, ^parent} = Entitlements.ensure_booking_capacity(parent, 0)
      assert {:ok, ^parent} = Entitlements.ensure_booking_capacity(parent, 1)
    end

    test "returns {:error, :booking_limit_exceeded} when explorer hits cap" do
      parent = parent_with_tier(:explorer)

      assert {:error, :booking_limit_exceeded} =
               Entitlements.ensure_booking_capacity(parent, 2)

      assert {:error, :booking_limit_exceeded} =
               Entitlements.ensure_booking_capacity(parent, 10)
    end

    test "returns {:ok, parent} for active tier at any count" do
      parent = parent_with_tier(:active)

      assert {:ok, ^parent} = Entitlements.ensure_booking_capacity(parent, 0)
      assert {:ok, ^parent} = Entitlements.ensure_booking_capacity(parent, 1000)
    end
  end

  describe "parent entitlements - monthly_booking_cap/1" do
    test "returns 2 for explorer tier" do
      parent = parent_with_tier(:explorer)
      assert Entitlements.monthly_booking_cap(parent) == 2
    end

    test "returns :unlimited for active tier" do
      parent = parent_with_tier(:active)
      assert Entitlements.monthly_booking_cap(parent) == :unlimited
    end
  end

  describe "parent entitlements - free_cancellations_per_month/1" do
    test "returns 0 for explorer tier" do
      parent = parent_with_tier(:explorer)
      assert Entitlements.free_cancellations_per_month(parent) == 0
    end

    test "returns 1 for active tier" do
      parent = parent_with_tier(:active)
      assert Entitlements.free_cancellations_per_month(parent) == 1
    end
  end

  describe "parent entitlements - progress_detail_level/1" do
    test "returns :basic for explorer tier" do
      parent = parent_with_tier(:explorer)
      assert Entitlements.progress_detail_level(parent) == :basic
    end

    test "returns :detailed for active tier" do
      parent = parent_with_tier(:active)
      assert Entitlements.progress_detail_level(parent) == :detailed
    end
  end

  describe "scope-based entitlements - can_initiate_messaging?/1" do
    test "returns false for explorer parent" do
      scope = %Scope{parent: parent_with_tier(:explorer), provider: nil}
      refute Entitlements.can_initiate_messaging?(scope)
    end

    test "returns true for active parent" do
      scope = %Scope{parent: parent_with_tier(:active), provider: nil}
      assert Entitlements.can_initiate_messaging?(scope)
    end

    test "returns true for any provider" do
      scope = %Scope{parent: nil, provider: provider_fixture()}
      assert Entitlements.can_initiate_messaging?(scope)
    end

    test "returns true for explorer parent when a provider is present" do
      scope = %Scope{
        parent: parent_with_tier(:explorer),
        provider: provider_fixture()
      }

      assert Entitlements.can_initiate_messaging?(scope)
    end

    test "returns false for empty scope" do
      scope = %Scope{parent: nil, provider: nil}
      refute Entitlements.can_initiate_messaging?(scope)
    end

    test "returns false for pure staff_member scope (provider: nil)" do
      scope = %Scope{
        staff_member: %{provider_id: "some-provider-id"},
        parent: nil,
        provider: nil
      }

      refute Entitlements.can_initiate_messaging?(scope)
    end

    test "returns true for staff_member scope with loaded provider (dual role)" do
      scope = %Scope{
        staff_member: %{provider_id: "some-provider-id"},
        parent: nil,
        provider: provider_fixture()
      }

      assert Entitlements.can_initiate_messaging?(scope)
    end

    test "catch-all returns false for unknown scope shape" do
      refute Entitlements.can_initiate_messaging?(%{unknown: :shape})
    end
  end

  describe "tier info functions" do
    test "parent_tier_info/1 returns full entitlement map for valid tier" do
      info = Entitlements.parent_tier_info(:explorer)

      assert info.monthly_booking_cap == 2
      assert info.free_cancellations == 0
      assert info.progress_level == :basic
      assert info.can_initiate_messaging == false
    end

    test "parent_tier_info/1 returns nil for invalid tier" do
      assert Entitlements.parent_tier_info(:invalid) == nil
    end
  end

  describe "all tiers functions" do
    test "all_parent_tiers/0 returns all tiers with entitlements" do
      tiers = Entitlements.all_parent_tiers()

      assert Keyword.has_key?(tiers, :explorer)
      assert Keyword.has_key?(tiers, :active)
      assert length(tiers) == 2
    end
  end

  describe "tier validation functions" do
    test "parent_tiers/0 returns list of valid parent tier atoms" do
      tiers = Entitlements.parent_tiers()

      assert :explorer in tiers
      assert :active in tiers
      assert length(tiers) == 2
    end

    test "valid_parent_tier?/1 returns true for valid tiers" do
      assert Entitlements.valid_parent_tier?(:explorer)
      assert Entitlements.valid_parent_tier?(:active)
    end

    test "valid_parent_tier?/1 returns false for invalid tiers" do
      refute Entitlements.valid_parent_tier?(:invalid)
      refute Entitlements.valid_parent_tier?(:starter)
      refute Entitlements.valid_parent_tier?("explorer")
      refute Entitlements.valid_parent_tier?(nil)
    end

    test "default_parent_tier/0 returns :explorer" do
      assert Entitlements.default_parent_tier() == :explorer
    end
  end
end
