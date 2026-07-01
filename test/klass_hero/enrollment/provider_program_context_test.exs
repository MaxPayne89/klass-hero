defmodule KlassHero.Enrollment.ProviderProgramContextTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.ProviderProgramContext

  describe "for_provider/1" do
    test "returns downcased programs_by_title for a provider with catalog entries" do
      provider = insert(:provider_profile_schema)
      insert(:program_schema, provider_id: provider.id, title: "Ballsports & Parkour")
      insert(:program_schema, provider_id: provider.id, title: "Organic Arts")

      assert {:ok,
              %{
                provider_id: provider_id,
                programs_by_title: lookup
              }} = ProviderProgramContext.for_provider(provider.id)

      assert provider_id == provider.id
      assert Map.has_key?(lookup, "ballsports & parkour")
      assert Map.has_key?(lookup, "organic arts")
      assert map_size(lookup) == 2
    end

    test "returns {:error, :no_programs} when the provider has no catalog entries" do
      provider = insert(:provider_profile_schema)
      assert {:error, :no_programs} = ProviderProgramContext.for_provider(provider.id)
    end

    test "returns {:error, {:title_collisions, titles}} when titles differ only by case" do
      provider = insert(:provider_profile_schema)
      insert(:program_schema, provider_id: provider.id, title: "Yoga")
      insert(:program_schema, provider_id: provider.id, title: "YOGA")

      assert {:error, {:title_collisions, titles}} =
               ProviderProgramContext.for_provider(provider.id)

      assert Enum.sort(titles) == ["YOGA", "Yoga"]
    end
  end
end
