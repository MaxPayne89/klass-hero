defmodule KlassHero.Family.ConsentsUnboxedTest do
  @moduledoc """
  The one consent test that runs *outside* the SQL sandbox.

  `Ecto.Adapters.SQL.Sandbox.Connection` proxies every statement and injects
  `mode: :savepoint` itself whenever no user-level transaction is open, so a
  sandboxed connection is never idle. That makes `mode: :savepoint` succeed in
  tests no matter how it is called — which is exactly how #1322 shipped green:
  `grant_consent/1` hardcoded the option, crashed on the LiveView path in
  production, and every test kept passing.

  `unboxed_run/2` checks out with `sandbox: false`, so there is no proxy and the
  connection really is idle. That is the only place this class of bug is visible.

  Consequences, all deliberate:

  - `async: false` and no `DataCase` — there is no sandbox to own, and the real
    test database is shared with no isolation.
  - Fixtures are built inside the block; rows created by a sandboxed process are
    invisible on this connection.
  - Nothing rolls back, so the block cleans up after itself.

  If you find yourself "fixing" this file back onto `DataCase`, read #1322 first:
  under the sandbox this test passes against the broken code.
  """

  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias KlassHero.Accounts.User
  alias KlassHero.Family
  alias KlassHero.Family.Child
  alias KlassHero.Family.Consent
  alias KlassHero.Family.ParentProfile
  alias KlassHero.Repo

  @consent_type "photo_marketing"

  test "grant_consent/1 succeeds when the caller holds no transaction" do
    Sandbox.unboxed_run(Repo, fn ->
      # Pins the precondition. Without it the test would still pass inside a
      # transaction and prove nothing — the exact trap #1322 fell into.
      refute Repo.in_transaction?()

      {parent, child} = insert_fixtures()

      try do
        assert {:ok, %Consent{} = consent} =
                 Family.grant_consent(%{
                   parent_id: parent.id,
                   child_id: child.id,
                   consent_type: @consent_type
                 })

        assert consent.child_id == child.id
        assert consent.parent_id == parent.id
        assert is_nil(consent.withdrawn_at)
      after
        cleanup(parent, child)
      end
    end)
  end

  defp insert_fixtures do
    user =
      Repo.insert!(%User{
        email: "consent-unboxed-#{System.unique_integer([:positive])}@example.com",
        name: "Unboxed Test User"
      })

    parent = Repo.insert!(%ParentProfile{identity_id: user.id, display_name: "Unboxed Parent"})
    child = Repo.insert!(%Child{first_name: "Unboxed", last_name: "Child"})

    {parent, child}
  end

  # FK order: consents restrict both parents and children, parents restricts users.
  defp cleanup(parent, child) do
    Repo.delete_all(from(c in Consent, where: c.child_id == ^child.id))
    Repo.delete_all(from(c in Child, where: c.id == ^child.id))
    Repo.delete_all(from(p in ParentProfile, where: p.id == ^parent.id))
    Repo.delete_all(from(u in User, where: u.id == ^parent.identity_id))
  end
end
