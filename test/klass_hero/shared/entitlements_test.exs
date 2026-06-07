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

  # Helper to create a provider with a specific tier
  defp provider_with_tier(tier) do
    %ProviderProfile{
      id: "provider-123",
      identity_id: "identity-123",
      business_name: "Test Business",
      subscription_tier: tier
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

  describe "provider entitlements - can_create_program?/2" do
    test "starter tier can create up to 2 programs" do
      provider = provider_with_tier(:starter)

      assert Entitlements.can_create_program?(provider, 0)
      assert Entitlements.can_create_program?(provider, 1)
      refute Entitlements.can_create_program?(provider, 2)
      refute Entitlements.can_create_program?(provider, 10)
    end

    test "professional tier can create up to 5 programs" do
      provider = provider_with_tier(:professional)

      assert Entitlements.can_create_program?(provider, 0)
      assert Entitlements.can_create_program?(provider, 4)
      refute Entitlements.can_create_program?(provider, 5)
    end

    test "business_plus tier has unlimited programs" do
      provider = provider_with_tier(:business_plus)

      assert Entitlements.can_create_program?(provider, 0)
      assert Entitlements.can_create_program?(provider, 100)
    end
  end

  describe "provider entitlements - commission_rate/1" do
    test "returns 0.18 for starter tier" do
      provider = provider_with_tier(:starter)
      assert Entitlements.commission_rate(provider) == 0.18
    end

    test "returns 0.12 for professional tier" do
      provider = provider_with_tier(:professional)
      assert Entitlements.commission_rate(provider) == 0.12
    end

    test "returns 0.08 for business_plus tier" do
      provider = provider_with_tier(:business_plus)
      assert Entitlements.commission_rate(provider) == 0.08
    end
  end

  describe "provider entitlements - media_entitlements/1" do
    test "starter tier has avatar only" do
      provider = provider_with_tier(:starter)
      assert Entitlements.media_entitlements(provider) == [:avatar]
    end

    test "professional tier has avatar, gallery, and video" do
      provider = provider_with_tier(:professional)
      assert Entitlements.media_entitlements(provider) == [:avatar, :gallery, :video]
    end

    test "business_plus tier has all media types" do
      provider = provider_with_tier(:business_plus)

      assert Entitlements.media_entitlements(provider) == [
               :avatar,
               :gallery,
               :video,
               :promotional
             ]
    end
  end

  describe "provider entitlements - max_programs/1" do
    test "returns 2 for starter tier" do
      provider = provider_with_tier(:starter)
      assert Entitlements.max_programs(provider) == 2
    end

    test "returns 5 for professional tier" do
      provider = provider_with_tier(:professional)
      assert Entitlements.max_programs(provider) == 5
    end

    test "returns :unlimited for business_plus tier" do
      provider = provider_with_tier(:business_plus)
      assert Entitlements.max_programs(provider) == :unlimited
    end
  end

  describe "provider entitlements - team_seats_allowed/1" do
    test "returns 1 for starter tier" do
      provider = provider_with_tier(:starter)
      assert Entitlements.team_seats_allowed(provider) == 1
    end

    test "returns 1 for professional tier" do
      provider = provider_with_tier(:professional)
      assert Entitlements.team_seats_allowed(provider) == 1
    end

    test "returns :unlimited for business_plus tier" do
      provider = provider_with_tier(:business_plus)
      assert Entitlements.team_seats_allowed(provider) == :unlimited
    end
  end

  describe "provider entitlements - can_add_team_member?/2" do
    test "starter tier allows up to 1 team member" do
      provider = provider_with_tier(:starter)

      assert Entitlements.can_add_team_member?(provider, 0)
      refute Entitlements.can_add_team_member?(provider, 1)
      refute Entitlements.can_add_team_member?(provider, 5)
    end

    test "professional tier allows up to 1 team member" do
      provider = provider_with_tier(:professional)

      assert Entitlements.can_add_team_member?(provider, 0)
      refute Entitlements.can_add_team_member?(provider, 1)
    end

    test "business_plus tier allows unlimited team members" do
      provider = provider_with_tier(:business_plus)

      assert Entitlements.can_add_team_member?(provider, 0)
      assert Entitlements.can_add_team_member?(provider, 100)
      assert Entitlements.can_add_team_member?(provider, 1000)
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

    test "returns true for any provider regardless of former tier" do
      for tier <- [:starter, :professional, :business_plus, nil] do
        scope = %Scope{parent: nil, provider: provider_with_tier(tier)}

        assert Entitlements.can_initiate_messaging?(scope),
               "expected provider with former tier #{inspect(tier)} to initiate messaging"
      end
    end

    test "returns true for explorer parent when a provider is present" do
      scope = %Scope{
        parent: parent_with_tier(:explorer),
        provider: provider_with_tier(:starter)
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
        provider: provider_with_tier(:starter)
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

    test "provider_tier_info/1 returns full entitlement map for valid tier" do
      info = Entitlements.provider_tier_info(:starter)

      assert info.max_programs == 2
      assert info.commission_rate == 0.18
      assert info.media == [:avatar]
      assert info.team_seats == 1
      assert info.can_initiate_messaging == false
    end

    test "provider_tier_info/1 returns nil for invalid tier" do
      assert Entitlements.provider_tier_info(:invalid) == nil
    end
  end

  describe "all tiers functions" do
    test "all_parent_tiers/0 returns all tiers with entitlements" do
      tiers = Entitlements.all_parent_tiers()

      assert Keyword.has_key?(tiers, :explorer)
      assert Keyword.has_key?(tiers, :active)
      assert length(tiers) == 2
    end

    test "all_provider_tiers/0 returns all tiers with entitlements" do
      tiers = Entitlements.all_provider_tiers()

      assert Keyword.has_key?(tiers, :starter)
      assert Keyword.has_key?(tiers, :professional)
      assert Keyword.has_key?(tiers, :business_plus)
      assert length(tiers) == 3
    end
  end

  describe "tier validation functions" do
    test "parent_tiers/0 returns list of valid parent tier atoms" do
      tiers = Entitlements.parent_tiers()

      assert :explorer in tiers
      assert :active in tiers
      assert length(tiers) == 2
    end

    test "provider_tiers/0 returns list of valid provider tier atoms" do
      tiers = Entitlements.provider_tiers()

      assert :starter in tiers
      assert :professional in tiers
      assert :business_plus in tiers
      assert length(tiers) == 3
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

    test "valid_provider_tier?/1 returns true for valid tiers" do
      assert Entitlements.valid_provider_tier?(:starter)
      assert Entitlements.valid_provider_tier?(:professional)
      assert Entitlements.valid_provider_tier?(:business_plus)
    end

    test "valid_provider_tier?/1 returns false for invalid tiers" do
      refute Entitlements.valid_provider_tier?(:invalid)
      refute Entitlements.valid_provider_tier?(:explorer)
      refute Entitlements.valid_provider_tier?("starter")
      refute Entitlements.valid_provider_tier?(nil)
    end

    test "default_parent_tier/0 returns :explorer" do
      assert Entitlements.default_parent_tier() == :explorer
    end

    test "default_provider_tier/0 returns :starter" do
      assert Entitlements.default_provider_tier() == :starter
    end
  end
end
