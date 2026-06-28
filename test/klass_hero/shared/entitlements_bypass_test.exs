defmodule KlassHero.Shared.EntitlementsBypassTest do
  use ExUnit.Case, async: false

  alias KlassHero.Accounts.Scope
  alias KlassHero.Family.ParentProfile
  alias KlassHero.Shared.Adapters.Driven.FeatureFlags.StubFeatureFlagsAdapter
  alias KlassHero.Shared.Entitlements

  defp parent_with_tier(tier) do
    %ParentProfile{
      id: "parent-123",
      identity_id: "identity-123",
      subscription_tier: tier
    }
  end

  describe "parent tier bypass enabled" do
    setup do
      start_supervised!({StubFeatureFlagsAdapter, name: StubFeatureFlagsAdapter})
      StubFeatureFlagsAdapter.set_enabled(:parent_tier_bypass)
      :ok
    end

    test "explorer parent gets unlimited booking cap" do
      parent = parent_with_tier(:explorer)
      assert Entitlements.monthly_booking_cap(parent) == :unlimited
    end

    test "explorer parent can create bookings at any count" do
      parent = parent_with_tier(:explorer)

      assert Entitlements.can_create_booking?(parent, 0)
      assert Entitlements.can_create_booking?(parent, 100)
      assert Entitlements.can_create_booking?(parent, 1000)
    end

    test "explorer parent gets 1 free cancellation" do
      parent = parent_with_tier(:explorer)
      assert Entitlements.free_cancellations_per_month(parent) == 1
    end

    test "explorer parent gets detailed progress" do
      parent = parent_with_tier(:explorer)
      assert Entitlements.progress_detail_level(parent) == :detailed
    end

    test "explorer parent can initiate messaging" do
      scope = %Scope{parent: parent_with_tier(:explorer), provider: nil}
      assert Entitlements.can_initiate_messaging?(scope)
    end

    test "active tier is unaffected (idempotent)" do
      parent = parent_with_tier(:active)

      assert Entitlements.monthly_booking_cap(parent) == :unlimited
      assert Entitlements.can_create_booking?(parent, 100)
      assert Entitlements.free_cancellations_per_month(parent) == 1
      assert Entitlements.progress_detail_level(parent) == :detailed
    end

    test "parent_tier_info/1 is NOT affected" do
      info = Entitlements.parent_tier_info(:explorer)

      assert info.monthly_booking_cap == 2
      assert info.free_cancellations == 0
      assert info.progress_level == :basic
      assert info.can_initiate_messaging == false
    end

    test "nil tier parent gets active limits when bypass enabled" do
      parent = parent_with_tier(nil)

      assert Entitlements.monthly_booking_cap(parent) == :unlimited
      assert Entitlements.can_create_booking?(parent, 100)
    end
  end

  describe "fail-closed behavior — parent bypass" do
    test "reverts to normal enforcement when flag is explicitly disabled" do
      start_supervised!({StubFeatureFlagsAdapter, name: StubFeatureFlagsAdapter})
      StubFeatureFlagsAdapter.set_enabled(:parent_tier_bypass)

      parent = parent_with_tier(:explorer)
      assert Entitlements.monthly_booking_cap(parent) == :unlimited

      StubFeatureFlagsAdapter.set_disabled(:parent_tier_bypass)

      assert Entitlements.monthly_booking_cap(parent) == 2
      refute Entitlements.can_create_booking?(parent, 2)
    end

    test "reverts to normal enforcement when flag system unavailable" do
      start_supervised!({StubFeatureFlagsAdapter, name: StubFeatureFlagsAdapter})
      StubFeatureFlagsAdapter.set_enabled(:parent_tier_bypass)

      parent = parent_with_tier(:explorer)
      assert Entitlements.monthly_booking_cap(parent) == :unlimited

      Agent.stop(StubFeatureFlagsAdapter)

      assert Entitlements.monthly_booking_cap(parent) == 2
      refute Entitlements.can_create_booking?(parent, 2)
    end
  end
end
