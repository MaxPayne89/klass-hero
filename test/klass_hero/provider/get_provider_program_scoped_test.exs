defmodule KlassHero.Provider.GetProviderProgramScopedTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory
  import KlassHero.ProviderFixtures, only: [provider_program_projection_fixture: 1]

  alias KlassHero.Provider

  describe "get_provider_program/2 (provider-scoped)" do
    setup do
      provider = insert(:provider_profile_schema)
      other_provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      provider_program_projection_fixture(
        provider_id: provider.id,
        program_id: program.id,
        name: "Art Club"
      )

      %{provider: provider, other_provider: other_provider, program_id: program.id}
    end

    test "returns the program when owned by the provider", ctx do
      assert {:ok, program} = Provider.get_provider_program(ctx.program_id, ctx.provider.id)
      assert program.program_id == ctx.program_id
    end

    test "returns not_found for a program owned by another provider", ctx do
      assert {:error, :not_found} = Provider.get_provider_program(ctx.program_id, ctx.other_provider.id)
    end

    test "returns not_found for a program that does not exist", ctx do
      assert {:error, :not_found} = Provider.get_provider_program(Ecto.UUID.generate(), ctx.provider.id)
    end

    test "foreign and missing are indistinguishable (no existence oracle)", ctx do
      foreign = Provider.get_provider_program(ctx.program_id, ctx.other_provider.id)
      missing = Provider.get_provider_program(Ecto.UUID.generate(), ctx.other_provider.id)

      assert foreign == missing
    end
  end
end
