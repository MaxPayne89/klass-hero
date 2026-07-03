defmodule KlassHero.Provider.Application.Commands.Providers.CreateProviderProfileTest do
  @moduledoc """
  Integration tests for CreateProviderProfile use case.

  Tests provider profile creation including:
  - Success path with valid attributes
  - ID auto-generation when not provided
  - Validation error wrapping as {:error, {:validation_error, errors}}
  - Duplicate identity_id error handling
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.Provider
  alias KlassHero.Provider.ProviderProfile

  defp valid_attrs(overrides \\ %{}) do
    user =
      KlassHero.AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

    Map.merge(
      %{
        identity_id: user.id,
        business_name: "Test Provider #{System.unique_integer([:positive])}"
      },
      overrides
    )
  end

  describe "create_provider_profile/1" do
    test "creates a provider profile with valid attributes" do
      attrs = valid_attrs()

      assert {:ok, profile} = Provider.create_provider_profile(attrs)
      assert %ProviderProfile{} = profile
      assert profile.identity_id == attrs.identity_id
      assert profile.business_name == attrs.business_name
      assert profile.verified == false
      assert profile.categories == []
    end

    test "auto-generates an id when not provided" do
      attrs = valid_attrs()
      refute Map.has_key?(attrs, :id)

      assert {:ok, profile} = Provider.create_provider_profile(attrs)
      assert is_binary(profile.id)
      assert {:ok, _} = Ecto.UUID.cast(profile.id)
    end

    test "returns validation error tuple for empty business_name" do
      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      attrs = %{identity_id: user.id, business_name: ""}

      assert {:error, {:validation_error, errors}} = Provider.create_provider_profile(attrs)
      assert is_list(errors)
      assert Enum.any?(errors, &String.contains?(&1, "Business name"))
    end

    test "returns validation error tuple for business_name exceeding 200 characters" do
      attrs = valid_attrs(%{business_name: String.duplicate("a", 201)})

      assert {:error, {:validation_error, errors}} = Provider.create_provider_profile(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "200"))
    end

    test "returns duplicate_resource error when identity already has a profile" do
      attrs = valid_attrs()
      assert {:ok, _} = Provider.create_provider_profile(attrs)

      assert {:error, :duplicate_resource} = Provider.create_provider_profile(attrs)
    end

    test "persists the profile to the database" do
      attrs = valid_attrs()

      assert {:ok, profile} = Provider.create_provider_profile(attrs)

      assert {:ok, fetched} = Provider.get_provider_by_identity(profile.identity_id)
      assert fetched.id == profile.id
      assert fetched.business_name == profile.business_name
    end
  end
end
