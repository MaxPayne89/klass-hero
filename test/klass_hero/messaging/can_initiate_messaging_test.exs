defmodule KlassHero.Messaging.CanInitiateMessagingTest do
  use ExUnit.Case, async: true

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging

  # Post-tier-removal (#925) matrix: any parent or provider may initiate
  # messaging; only a pure staff-only scope (staff_member set, no provider,
  # no parent) and an unknown scope shape are denied.
  @cases [
    {"parent scope", %Scope{parent: %{}, provider: nil}, true},
    {"provider scope", %Scope{parent: nil, provider: %{id: "p1"}}, true},
    {"parent + provider dual scope", %Scope{parent: %{}, provider: %{id: "p1"}}, true},
    {"staff dual role (provider loaded)",
     %Scope{staff_member: %{provider_id: "p1"}, parent: nil, provider: %{id: "p1"}}, true},
    {"bare map with only provider key", %{provider: %{id: "p1"}}, true},
    {"empty scope", %Scope{parent: nil, provider: nil}, false},
    {"pure staff-only scope (no provider)", %Scope{staff_member: %{provider_id: "p1"}, parent: nil, provider: nil},
     false},
    {"unknown scope shape", %{unknown: :shape}, false}
  ]

  describe "can_initiate_messaging?/1" do
    for {label, scope, expected} <- @cases do
      test "#{label} -> #{expected}" do
        assert Messaging.can_initiate_messaging?(unquote(Macro.escape(scope))) == unquote(expected)
      end
    end
  end
end
