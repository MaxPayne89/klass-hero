defmodule KlassHero.ProgramCatalog.GetProgramForProviderTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.ProgramCatalog

  describe "get_program_for_provider/2" do
    test "returns the program when the provider owns it" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      assert {:ok, found} = ProgramCatalog.get_program_for_provider(provider.id, program.id)
      assert found.id == program.id
    end

    # Foreign, unknown and malformed all collapse to the same atom — that
    # indistinguishability is the point, so they belong in one table.
    test "returns :not_found for any id the provider can't claim" do
      provider = insert(:provider_profile_schema)
      foreign_program = insert(:program_schema, provider_id: insert(:provider_profile_schema).id)

      cases = [
        {"another provider's program", foreign_program.id},
        {"an unknown program id", Ecto.UUID.generate()},
        {"a malformed program id", "not-a-uuid"}
      ]

      for {label, program_id} <- cases do
        assert {:error, :not_found} = ProgramCatalog.get_program_for_provider(provider.id, program_id),
               "expected :not_found for #{label}"
      end
    end
  end
end
