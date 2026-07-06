defmodule KlassHero.Provider.GetBusinessNamesTest do
  use KlassHero.DataCase, async: true

  import KlassHero.ProviderFixtures

  alias KlassHero.Provider

  describe "get_business_names/1" do
    test "maps known provider ids to their business names" do
      a = provider_profile_fixture(%{business_name: "Alpha Kids"})
      b = provider_profile_fixture(%{business_name: "Beta Camps"})

      assert Provider.get_business_names([a.id, b.id]) == %{
               a.id => "Alpha Kids",
               b.id => "Beta Camps"
             }
    end

    test "returns an empty map for an empty list without hitting the DB" do
      assert Provider.get_business_names([]) == %{}
    end

    test "omits ids that do not resolve to a provider" do
      a = provider_profile_fixture(%{business_name: "Alpha Kids"})
      missing = Ecto.UUID.generate()

      assert Provider.get_business_names([a.id, missing]) == %{a.id => "Alpha Kids"}
    end
  end
end
