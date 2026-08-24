defmodule KlassHeroWeb.Helpers.ProviderBrandingTest do
  use ExUnit.Case, async: true

  alias KlassHero.Provider.ProviderProfile
  alias KlassHeroWeb.Helpers.ProviderBranding

  describe "filled_networks/1" do
    test "returns only the networks carrying a value" do
      provider = %ProviderProfile{
        instagram_url: "https://instagram.com/x",
        linkedin_url: "https://linkedin.com/company/x"
      }

      assert ProviderBranding.filled_networks(provider) == [:instagram_url, :linkedin_url]
    end

    test "treats nil and blank the same as unset" do
      # A blank column is reachable through a backfill or raw SQL, and it must
      # open the picker rather than an empty row the provider did not ask for.
      provider = %ProviderProfile{instagram_url: nil, facebook_url: "", tiktok_url: "   "}

      assert ProviderBranding.filled_networks(provider) == []
    end

    test "preserves the entity's display order, not the struct's" do
      provider = %ProviderProfile{
        linkedin_url: "https://linkedin.com/company/x",
        instagram_url: "https://instagram.com/x"
      }

      assert ProviderBranding.filled_networks(provider) == [:instagram_url, :linkedin_url]
    end
  end

  describe "reveal/2" do
    test "adds a known network" do
      assert ProviderBranding.reveal([], "instagram_url") == [:instagram_url]
    end

    test "appends rather than prepends, so rows do not reorder as they are added" do
      assert ProviderBranding.reveal([:instagram_url], "facebook_url") == [
               :instagram_url,
               :facebook_url
             ]
    end

    test "is idempotent" do
      assert ProviderBranding.reveal([:instagram_url], "instagram_url") == [:instagram_url]
    end

    test "ignores a value that is not a social field" do
      # The param comes from the client. Resolving against social_link_fields/0
      # rather than String.to_existing_atom/1 means a crafted value is dropped,
      # not raised on — and can never name a non-social column.
      for junk <- ["business_name", "not_a_field", "", "Elixir.Kernel"] do
        assert ProviderBranding.reveal([:instagram_url], junk) == [:instagram_url]
      end
    end

    test "covers every network the entity declares" do
      # Guards against the picker silently dropping a network added to the schema.
      revealed =
        Enum.reduce(ProviderProfile.social_link_fields(), [], fn field, acc ->
          ProviderBranding.reveal(acc, Atom.to_string(field))
        end)

      assert revealed == ProviderProfile.social_link_fields()
    end
  end
end
