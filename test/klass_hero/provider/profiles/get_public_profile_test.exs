defmodule KlassHero.Provider.Profiles.GetPublicProfileTest do
  use KlassHero.DataCase, async: true

  import KlassHero.ProviderFixtures

  alias KlassHero.Provider

  describe "get_public_profile/1" do
    test "returns an active profile" do
      profile = provider_profile_fixture(business_name: "Starlight Coaching")

      assert {:ok, %{id: id, business_name: "Starlight Coaching"}} =
               Provider.get_public_profile(profile.id)

      assert id == profile.id
    end

    test "hides a draft profile" do
      profile = provider_profile_fixture(profile_status: :draft)

      # Not a distinct error: a draft profile is indistinguishable from a missing
      # one to a stranger, so the id cannot be probed for existence.
      assert Provider.get_public_profile(profile.id) == {:error, :not_found}
      assert {:ok, _} = Provider.get_provider_profile(profile.id)
    end

    test "returns not_found for an unknown id" do
      assert Provider.get_public_profile(Ecto.UUID.generate()) == {:error, :not_found}
    end

    test "returns not_found for a malformed id rather than raising" do
      # A public route makes this id user-typed. Repo.get/2 on a binary_id raises
      # Ecto.Query.CastError for a non-UUID, which would be a 500 on /providers/x.
      for id <- ["not-a-uuid", "", "1234567890123456", "../etc/passwd"] do
        assert Provider.get_public_profile(id) == {:error, :not_found},
               "expected #{inspect(id)} to be rejected without raising"
      end
    end

    test "returns not_found for a non-binary id" do
      assert Provider.get_public_profile(nil) == {:error, :not_found}
    end
  end
end
