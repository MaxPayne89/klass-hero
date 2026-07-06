defmodule KlassHero.ProgramCatalog.ListProgramIdsForProviderTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.ProgramCatalog

  describe "list_program_ids_for_provider/1" do
    test "returns the write-model program ids owned by the provider" do
      provider = insert(:provider_profile_schema)
      p1 = insert(:program_schema, provider_id: provider.id)
      p2 = insert(:program_schema, provider_id: provider.id)
      _other = insert(:program_schema, provider_id: insert(:provider_profile_schema).id)

      assert Enum.sort(ProgramCatalog.list_program_ids_for_provider(provider.id)) ==
               Enum.sort([p1.id, p2.id])
    end

    test "returns an empty list for a provider with no programs" do
      provider = insert(:provider_profile_schema)
      assert ProgramCatalog.list_program_ids_for_provider(provider.id) == []
    end
  end
end
