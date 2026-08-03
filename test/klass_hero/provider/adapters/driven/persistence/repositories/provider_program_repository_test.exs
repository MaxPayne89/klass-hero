defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.ProviderProgramRepositoryTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.ProviderProgramRepository
  alias KlassHero.Provider.ProviderProgram
  alias KlassHero.Repo

  defp insert_row!(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    defaults = %{
      program_id: Ecto.UUID.generate(),
      provider_id: Ecto.UUID.generate(),
      name: "Drawing Club",
      inserted_at: now,
      updated_at: now
    }

    Repo.insert!(struct(ProviderProgram, Map.merge(defaults, attrs)))
  end

  describe "get_by_id/1" do
    test "returns {:ok, struct} for a known program_id" do
      row = insert_row!(%{name: "Robotics"})

      assert {:ok, %ProviderProgram{program_id: id, name: "Robotics"}} =
               ProviderProgramRepository.get_by_id(row.program_id)

      assert id == row.program_id
    end

    test "returns {:error, :not_found} for unknown id" do
      assert {:error, :not_found} =
               ProviderProgramRepository.get_by_id(Ecto.UUID.generate())
    end
  end

  describe "list_by_provider/1" do
    test "returns only rows for the given provider, ordered by name asc" do
      provider_id = Ecto.UUID.generate()
      insert_row!(%{provider_id: provider_id, name: "Chess"})
      insert_row!(%{provider_id: provider_id, name: "Art"})
      insert_row!(%{provider_id: Ecto.UUID.generate(), name: "Stranger"})

      rows = ProviderProgramRepository.list_by_provider(provider_id)

      assert length(rows) == 2
      assert Enum.map(rows, & &1.name) == ["Art", "Chess"]
      assert Enum.all?(rows, &(&1.provider_id == provider_id))
    end

    test "returns [] for provider with no programs" do
      assert ProviderProgramRepository.list_by_provider(Ecto.UUID.generate()) == []
    end
  end
end
