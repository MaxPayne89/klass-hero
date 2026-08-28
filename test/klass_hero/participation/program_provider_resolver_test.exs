defmodule KlassHero.Participation.ProgramProviderResolverTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Participation.ProgramProviderResolver

  describe "resolve_provider_id/1" do
    test "returns provider_id for an existing program" do
      provider = KlassHero.Factory.insert(:provider_profile_schema)
      program = KlassHero.Factory.insert(:program_schema, provider_id: provider.id)

      assert {:ok, provider_id} = ProgramProviderResolver.resolve_provider_id(program.id)
      assert provider_id == provider.id
    end

    test "returns :program_not_found when program does not exist" do
      non_existent_id = Ecto.UUID.generate()

      assert {:error, :program_not_found} =
               ProgramProviderResolver.resolve_provider_id(non_existent_id)
    end
  end

  describe "resolve_provider_details/1" do
    test "returns provider_id and program_title for an existing program" do
      provider = KlassHero.Factory.insert(:provider_profile_schema)
      program = KlassHero.Factory.insert(:program_schema, provider_id: provider.id)

      assert {:ok, details} = ProgramProviderResolver.resolve_provider_details(program.id)
      assert details.provider_id == provider.id
      assert details.program_title == program.title
    end

    test "returns :program_not_found when program does not exist" do
      non_existent_id = Ecto.UUID.generate()

      assert {:error, :program_not_found} =
               ProgramProviderResolver.resolve_provider_details(non_existent_id)
    end
  end
end
