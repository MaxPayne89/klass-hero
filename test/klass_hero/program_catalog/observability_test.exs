defmodule KlassHero.ProgramCatalog.ObservabilityTest do
  use KlassHero.DataCase, async: false
  use KlassHero.TracingHelpers

  alias KlassHero.ProgramCatalog
  alias KlassHero.ProviderFixtures

  describe "context_span + Ecto bridge integration" do
    test "create_program opens a context span with a nested db child span" do
      provider = ProviderFixtures.provider_profile_fixture()

      assert {:ok, _program} =
               ProgramCatalog.create_program(%{
                 provider_id: provider.id,
                 title: "Observability Program",
                 description: "Verifies tracing instrumentation",
                 category: "arts",
                 price: Decimal.new("25.00")
               })

      assert_span("ProgramCatalog.create_program/1",
        "context.name": "ProgramCatalog",
        "context.operation": "create_program"
      )

      assert_span("programs.query")
    end
  end
end
