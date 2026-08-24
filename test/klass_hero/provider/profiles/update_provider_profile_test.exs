defmodule KlassHero.Provider.Profiles.UpdateProviderProfileTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider
  alias KlassHero.Provider.ProviderProfile

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

  describe "update_provider_profile/2 branding fields (#1302)" do
    # Reloads from the DB rather than asserting the returned struct. Three
    # independent allowlists can drop a field on the way to the table
    # (@profile_update_fields, @profile_persist_fields, changeset/2's cast), and
    # the latter two still return the in-memory value they never persisted — so a
    # return-value assertion goes green on a field that was silently discarded.
    for {field, value} <- [
          tagline: "Play-based learning",
          cover_image_url: "https://example.com/cover.png",
          instagram_url: "https://instagram.com/example",
          facebook_url: "https://facebook.com/example",
          tiktok_url: "https://tiktok.com/@example",
          youtube_url: "https://youtube.com/@example",
          linkedin_url: "https://linkedin.com/company/example"
        ] do
      test "persists #{field} through to the database", %{provider: provider} do
        assert {:ok, _} =
                 Provider.update_provider_profile(provider.id, %{unquote(field) => unquote(value)})

        reloaded = Repo.get!(ProviderProfile, provider.id)
        assert Map.fetch!(reloaded, unquote(field)) == unquote(value)
      end
    end

    test "rejects a tagline over 150 characters", %{provider: provider} do
      assert {:error, {:validation_error, _}} =
               Provider.update_provider_profile(provider.id, %{tagline: String.duplicate("a", 151)})
    end

    test "rejects a social link that is not https", %{provider: provider} do
      assert {:error, {:validation_error, _}} =
               Provider.update_provider_profile(provider.id, %{instagram_url: "http://example.com"})
    end

    test "a blank value already in the column does not block unrelated edits", %{provider: provider} do
      # validate/1 re-validates the whole struct on every update, so treating ""
      # as invalid would let one blank column — however it got there — permanently
      # block every later edit of this provider. Write "" past the form path to
      # prove it does not.
      Repo.update_all(
        from(p in ProviderProfile, where: p.id == ^provider.id),
        set: [instagram_url: "", tagline: ""]
      )

      assert {:ok, _} = Provider.update_provider_profile(provider.id, %{description: "Still editable"})

      assert Repo.get!(ProviderProfile, provider.id).description == "Still editable"
    end

    test "persists a scheme-less social link as https", %{provider: provider} do
      # This path discards the pure core's struct and persists the changeset's,
      # so it is the changeset that has to rewrite. Its sibling in
      # complete_provider_profile_test.exs covers the opposite arrangement —
      # normalizing only one of the two looks like a whole fix.
      assert {:ok, _} =
               Provider.update_provider_profile(provider.id, %{instagram_url: "instagram.com/starlight"})

      assert Repo.get!(ProviderProfile, provider.id).instagram_url ==
               "https://instagram.com/starlight"
    end

    test "leaves branding fields nil when never set", %{provider: provider} do
      assert {:ok, _} = Provider.update_provider_profile(provider.id, %{description: "unrelated"})

      reloaded = Repo.get!(ProviderProfile, provider.id)
      assert is_nil(reloaded.tagline)
      assert is_nil(reloaded.cover_image_url)
    end
  end
end
