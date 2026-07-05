defmodule KlassHero.Messaging.Adapters.Driven.Provider.ProviderUserResolverTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.Adapters.Driven.Provider.ProviderUserResolver

  describe "get_user_id_for_provider/1" do
    test "returns user_id for a valid provider profile ID" do
      user = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: user.id)

      user_id = user.id
      assert {:ok, ^user_id} = ProviderUserResolver.get_user_id_for_provider(provider.id)
    end

    test "returns not_found for a non-existent provider ID" do
      assert {:error, :not_found} =
               ProviderUserResolver.get_user_id_for_provider(Ecto.UUID.generate())
    end
  end
end
