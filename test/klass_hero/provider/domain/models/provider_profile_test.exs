defmodule KlassHero.Provider.Domain.Models.ProviderProfileTest do
  @moduledoc """
  Tests for the ProviderProfile domain entity.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.Domain.Models.ProviderProfile

  describe "new/1 with valid attributes" do
    test "creates provider profile with all fields" do
      attrs = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        identity_id: "660e8400-e29b-41d4-a716-446655440001",
        business_name: "Kids Sports Academy",
        description: "Premier youth sports training",
        phone: "+1234567890",
        website: "https://example.com",
        address: "123 Main St",
        logo_url: "https://example.com/logo.png",
        categories: ["sports", "outdoor"]
      }

      assert {:ok, profile} = ProviderProfile.new(attrs)
      assert profile.id == attrs.id
      assert profile.identity_id == attrs.identity_id
      assert profile.business_name == "Kids Sports Academy"
      assert profile.verified == false
      assert profile.categories == ["sports", "outdoor"]
    end

    test "creates provider profile with only required fields" do
      attrs = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        identity_id: "660e8400-e29b-41d4-a716-446655440001",
        business_name: "My Business"
      }

      assert {:ok, profile} = ProviderProfile.new(attrs)
      assert profile.business_name == "My Business"
      assert profile.verified == false
      assert profile.categories == []
    end
  end

  describe "new/1 validation errors" do
    test "returns error when identity_id is empty" do
      attrs = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        identity_id: "",
        business_name: "My Business"
      }

      assert {:error, errors} = ProviderProfile.new(attrs)
      assert "Identity ID cannot be empty" in errors
    end

    test "returns error when business_name is empty" do
      attrs = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        identity_id: "uuid-123",
        business_name: ""
      }

      assert {:error, errors} = ProviderProfile.new(attrs)
      assert "Business name cannot be empty" in errors
    end

    test "returns error when business_name exceeds 200 characters" do
      attrs = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        identity_id: "uuid-123",
        business_name: String.duplicate("a", 201)
      }

      assert {:error, errors} = ProviderProfile.new(attrs)
      assert "Business name must be 200 characters or less" in errors
    end

    test "returns error when categories is not a list" do
      attrs = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        identity_id: "uuid-123",
        business_name: "My Business",
        categories: "sports"
      }

      assert {:error, errors} = ProviderProfile.new(attrs)
      assert "Categories must be a list" in errors
    end
  end

  describe "valid?/1" do
    test "returns true for valid provider profile" do
      {:ok, profile} =
        ProviderProfile.new(%{
          id: "550e8400-e29b-41d4-a716-446655440000",
          identity_id: "uuid-123",
          business_name: "My Business"
        })

      assert ProviderProfile.valid?(profile)
    end

    test "returns false for provider profile with empty business_name" do
      profile = %ProviderProfile{
        id: "550e8400-e29b-41d4-a716-446655440000",
        identity_id: "uuid-123",
        business_name: ""
      }

      refute ProviderProfile.valid?(profile)
    end
  end
end
