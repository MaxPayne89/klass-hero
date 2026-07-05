defmodule KlassHero.Provider.Profiles.CompleteProviderProfileTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider

  setup do
    provider = KlassHero.Factory.insert(:draft_provider_profile_schema)
    domain_provider = provider

    %{provider: domain_provider}
  end

  describe "complete_provider_profile/2" do
    test "completes a draft profile with valid attrs", %{provider: provider} do
      attrs = %{
        business_name: "Youth Sports Academy",
        description: "Premier youth sports training",
        phone: "+1234567890",
        website: "https://example.com",
        address: "123 Main St"
      }

      assert {:ok, completed} = Provider.complete_provider_profile(provider.id, attrs)
      assert completed.profile_status == :active
      assert completed.business_name == "Youth Sports Academy"
      assert completed.description == "Premier youth sports training"
      assert completed.phone == "+1234567890"
      assert completed.id == provider.id
    end

    test "preserves identity_id", %{provider: provider} do
      attrs = %{
        business_name: "New Name",
        description: "A description"
      }

      assert {:ok, completed} = Provider.complete_provider_profile(provider.id, attrs)
      assert completed.identity_id == provider.identity_id
    end

    test "returns :not_found for non-existent provider" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = Provider.complete_provider_profile(fake_id, %{})
    end

    test "returns :already_active for an active profile" do
      active_provider = KlassHero.Factory.insert(:provider_profile_schema)
      domain = active_provider

      assert {:error, :already_active} =
               Provider.complete_provider_profile(domain.id, %{description: "test"})
    end

    test "returns validation error for invalid attrs", %{provider: provider} do
      attrs = %{business_name: "", description: "Valid"}

      assert {:error, {:validation_error, errors}} =
               Provider.complete_provider_profile(provider.id, attrs)

      assert is_list(errors)
    end
  end
end
