defmodule KlassHero.Provider.Profiles.UpdateProviderProfileTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider

  setup do
    provider = KlassHero.Factory.insert(:provider_profile_schema)

    %{provider: provider}
  end

  describe "update_provider_profile/2" do
    test "updates description successfully", %{provider: provider} do
      attrs = %{description: "Updated business description"}

      assert {:ok, updated} = Provider.update_provider_profile(provider.id, attrs)
      assert updated.description == "Updated business description"
      assert updated.id == provider.id
    end

    test "updates logo_url successfully", %{provider: provider} do
      attrs = %{logo_url: "https://storage.example.com/logos/new-logo.png"}

      assert {:ok, updated} = Provider.update_provider_profile(provider.id, attrs)
      assert updated.logo_url == "https://storage.example.com/logos/new-logo.png"
    end

    test "updates both description and logo_url", %{provider: provider} do
      attrs = %{
        description: "New description",
        logo_url: "https://storage.example.com/logos/logo.png"
      }

      assert {:ok, updated} = Provider.update_provider_profile(provider.id, attrs)
      assert updated.description == "New description"
      assert updated.logo_url == "https://storage.example.com/logos/logo.png"
    end

    test "returns error for non-existent provider" do
      fake_id = Ecto.UUID.generate()
      attrs = %{description: "Something"}

      assert {:error, :not_found} = Provider.update_provider_profile(fake_id, attrs)
    end

    test "returns validation error for description exceeding max length", %{provider: provider} do
      long_desc = String.duplicate("a", 1001)
      attrs = %{description: long_desc}

      assert {:error, {:validation_error, errors}} =
               Provider.update_provider_profile(provider.id, attrs)

      assert is_list(errors)
    end

    test "preserves existing fields when updating only description", %{provider: provider} do
      original_name = provider.business_name
      attrs = %{description: "Only updating description"}

      assert {:ok, updated} = Provider.update_provider_profile(provider.id, attrs)
      assert updated.business_name == original_name
      assert updated.description == "Only updating description"
    end
  end
end
