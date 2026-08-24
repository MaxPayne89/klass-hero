defmodule KlassHeroWeb.Helpers.ProviderDisplayTest do
  use KlassHero.DataCase, async: true

  import KlassHero.ProviderFixtures

  alias KlassHeroWeb.Helpers.ProviderDisplay

  describe "public_view/1" do
    test "returns the hero view map for an active provider" do
      profile = provider_profile_fixture(business_name: "Starlight Coaching")

      assert %{business_name: "Starlight Coaching", initials: "SC", trust_state: :unverified} =
               ProviderDisplay.public_view(profile.id)
    end

    test "returns nil for draft, unknown and malformed ids" do
      draft = provider_profile_fixture(profile_status: :draft)

      for id <- [draft.id, Ecto.UUID.generate(), "not-a-uuid", nil] do
        assert ProviderDisplay.public_view(id) == nil,
               "expected #{inspect(id)} to have no public view"
      end
    end

    test "keeps the identity when the trust lookup fails, dropping only the badge" do
      # The badge is additive, the identity is the content. Without the rescue a
      # vetting-lookup failure blanks the whole provider card.
      profile = provider_profile_fixture(business_name: "Starlight Coaching")

      Mimic.stub(KlassHero.Provider, :get_trust_states, fn _ids ->
        raise DBConnection.ConnectionError, "vetting lookup exploded"
      end)

      assert %{business_name: "Starlight Coaching", trust_state: :unverified} =
               ProviderDisplay.public_view(profile.id)
    end
  end
end
