defmodule KlassHero.Accounts.ObservabilityTest do
  @moduledoc """
  Proves Option E end-to-end on the flattened Accounts context: a state-changing
  public function opens a coarse `context_span`, under which the Ecto bridge nests
  a fine-grained `*.query` child span — with no per-call instrumentation in the
  context body. Mirrors `KlassHero.Family.ObservabilityTest`.
  """

  use KlassHero.DataCase, async: false
  use KlassHero.TracingHelpers

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts

  describe "context_span + Ecto bridge integration" do
    test "register_user opens a context span with a nested db child span" do
      assert {:ok, _user} = Accounts.register_user(valid_user_attributes())

      assert_span("Accounts.register_user/1",
        "context.name": "Accounts",
        "context.operation": "register_user"
      )

      assert_span("users.query")
    end
  end
end
