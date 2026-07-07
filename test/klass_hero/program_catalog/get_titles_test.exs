defmodule KlassHero.ProgramCatalog.GetTitlesTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.ProgramCatalog

  describe "get_titles/1" do
    test "maps program ids to their titles" do
      provider = insert(:provider_profile_schema)
      p1 = insert(:program_schema, provider_id: provider.id, title: "Science Explorers")
      p2 = insert(:program_schema, provider_id: provider.id, title: "Forest Friends")

      assert ProgramCatalog.get_titles([p1.id, p2.id]) == %{
               p1.id => "Science Explorers",
               p2.id => "Forest Friends"
             }
    end

    test "returns an empty map for an empty id list" do
      assert ProgramCatalog.get_titles([]) == %{}
    end

    test "omits ids with no matching program" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id, title: "Science Explorers")
      unknown_id = Ecto.UUID.generate()

      result = ProgramCatalog.get_titles([program.id, unknown_id])

      assert result[program.id] == "Science Explorers"
      refute Map.has_key?(result, unknown_id)
    end
  end
end
