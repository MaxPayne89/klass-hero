defmodule KlassHero.Provider.ObservabilityTest do
  @moduledoc """
  Proves Option E end-to-end on the Provider context, the sibling of the
  Accounts/Family/ProgramCatalog observability tests.

  Provider needs its own because it is the only context built as a pure
  delegate facade — 102 of `provider.ex`'s 104 public functions are
  `defdelegate`, so every span it emits comes from a submodule. While
  `context.name` was derived from the module's *last* segment, that meant
  Provider reported `Staff`, `Profiles` and `Assignments` and never itself:
  a 7-day production breakdown listed all three and no `Provider` at all,
  and the context-level error trigger that exists for Enrollment could not
  be written here (#1424).
  """

  use KlassHero.DataCase, async: false
  use KlassHero.TracingHelpers

  alias KlassHero.Provider

  describe "context_span + Ecto bridge integration" do
    test "create_provider_profile opens a Provider context span with a nested db child span" do
      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      attrs = %{
        identity_id: user.id,
        business_name: "Observability Co #{System.unique_integer([:positive])}"
      }

      assert {:ok, _profile} = Provider.create_provider_profile(attrs)

      # The span name still carries the submodule — that is the module path, and it
      # is correct. `context.name` names the bounded context; the two are not the
      # same question.
      assert_span("Provider.Profiles.create_provider_profile/1",
        "context.name": "Provider",
        "context.operation": "create_provider_profile"
      )

      # `providers`, not `provider_profiles` — the schema is ProviderProfile but the
      # table it maps to is not.
      assert_span("providers.query")
    end
  end
end
