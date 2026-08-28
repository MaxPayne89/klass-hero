defmodule KlassHero.ProgramCatalog.ListCurrentProgramsForProviderTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.ProgramCatalog

  defp titles(provider_id) do
    provider_id |> ProgramCatalog.list_current_programs_for_provider() |> Enum.map(& &1.title)
  end

  describe "list_current_programs_for_provider/1" do
    test "returns only this provider's programs" do
      provider_id = insert(:provider_profile_schema).id
      insert(:program_schema, provider_id: provider_id, title: "Ours")
      insert(:program_schema, provider_id: insert(:provider_profile_schema).id, title: "Theirs")

      assert titles(provider_id) == ["Ours"]
    end

    test "orders by title ascending" do
      provider_id = insert(:provider_profile_schema).id

      for title <- ["Zebra", "Apple", "Mango"] do
        insert(:program_schema, provider_id: provider_id, title: title)
      end

      assert titles(provider_id) == ["Apple", "Mango", "Zebra"]
    end

    test "excludes expired programs, unlike list_programs_for_provider/1" do
      provider_id = insert(:provider_profile_schema).id
      insert(:program_schema, provider_id: provider_id, title: "Open", end_date: nil)

      insert(:program_schema,
        provider_id: provider_id,
        title: "Over",
        end_date: Date.add(Date.utc_today(), -1)
      )

      assert titles(provider_id) == ["Open"]

      # Pin the contrast: the sibling function is documented as including expired
      # (#610) and the provider dashboard depends on that, so this is a genuine
      # second query rather than one that could replace it.
      assert provider_id
             |> ProgramCatalog.list_programs_for_provider()
             |> Enum.map(& &1.title) == ["Open", "Over"]
    end

    test "a listing ending today is still current" do
      provider_id = insert(:provider_profile_schema).id

      insert(:program_schema,
        provider_id: provider_id,
        title: "Last day",
        end_date: Date.utc_today()
      )

      assert titles(provider_id) == ["Last day"]
    end

    test "returns an empty list for a provider with no programs" do
      assert titles(Ecto.UUID.generate()) == []
    end
  end
end
