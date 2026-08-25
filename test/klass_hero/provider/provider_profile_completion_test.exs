defmodule KlassHero.Provider.ProviderProfileCompletionTest do
  @moduledoc """
  Tests for ProviderProfile profile_status field and complete_profile/2.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.ProviderProfile

  @valid_base_attrs %{
    id: "550e8400-e29b-41d4-a716-446655440000",
    identity_id: "660e8400-e29b-41d4-a716-446655440001",
    business_name: "My Business"
  }

  describe "new/1 profile_status" do
    test "defaults to :active when not specified" do
      assert {:ok, profile} = ProviderProfile.new(@valid_base_attrs)
      assert profile.profile_status == :active
    end

    test "accepts :draft profile_status" do
      attrs = Map.put(@valid_base_attrs, :profile_status, :draft)
      assert {:ok, profile} = ProviderProfile.new(attrs)
      assert profile.profile_status == :draft
    end

    test "accepts :active profile_status" do
      attrs = Map.put(@valid_base_attrs, :profile_status, :active)
      assert {:ok, profile} = ProviderProfile.new(attrs)
      assert profile.profile_status == :active
    end

    test "rejects invalid profile_status" do
      attrs = Map.put(@valid_base_attrs, :profile_status, :invalid)
      assert {:error, errors} = ProviderProfile.new(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "profile_status"))
    end
  end

  describe "draft?/1" do
    test "returns true for draft profile" do
      {:ok, profile} = ProviderProfile.new(Map.put(@valid_base_attrs, :profile_status, :draft))
      assert ProviderProfile.draft?(profile)
    end

    test "returns false for active profile" do
      {:ok, profile} = ProviderProfile.new(@valid_base_attrs)
      refute ProviderProfile.draft?(profile)
    end
  end

  describe "complete_profile/2" do
    setup do
      {:ok, draft} =
        ProviderProfile.new(%{
          id: "550e8400-e29b-41d4-a716-446655440000",
          identity_id: "660e8400-e29b-41d4-a716-446655440001",
          business_name: "My Business",
          profile_status: :draft
        })

      %{draft: draft}
    end

    test "completes a draft profile with valid attrs", %{draft: draft} do
      attrs = %{
        business_name: "Youth Sports Academy",
        description: "Premier youth sports training",
        phone: "+1234567890",
        website: "https://example.com",
        address: "123 Main St",
        categories: ["sports", "outdoor"]
      }

      assert {:ok, completed} = ProviderProfile.complete_profile(draft, attrs)
      assert completed.profile_status == :active
      assert completed.business_name == "Youth Sports Academy"
      assert completed.description == "Premier youth sports training"
      assert completed.phone == "+1234567890"
      assert completed.categories == ["sports", "outdoor"]
    end

    test "preserves identity_id and id", %{draft: draft} do
      attrs = %{description: "A description", business_name: "New Name"}

      assert {:ok, completed} = ProviderProfile.complete_profile(draft, attrs)
      assert completed.id == draft.id
      assert completed.identity_id == draft.identity_id
    end

    test "returns error for invalid attrs", %{draft: draft} do
      attrs = %{business_name: "", description: "Valid description"}

      assert {:error, errors} = ProviderProfile.complete_profile(draft, attrs)
      assert Enum.any?(errors, &String.contains?(&1, "Business name"))
    end

    test "returns :already_active for an active profile" do
      {:ok, active} = ProviderProfile.new(@valid_base_attrs)

      assert {:error, :already_active} =
               ProviderProfile.complete_profile(active, %{description: "test"})
    end
  end
end
