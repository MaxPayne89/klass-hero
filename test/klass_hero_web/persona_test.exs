defmodule KlassHeroWeb.PersonaTest do
  @moduledoc """
  The seam between "which personas does this person hold" and "what do they see".

  It replaced `RoleRouting`, whose fixed provider > staff > parent precedence
  made a dual-persona user's chosen surface unreachable. Precedence survives as
  the *default*, not the rule.

  Two entry points exist on purpose, and the split is load-bearing:

    * `resolve/1` is authoritative and takes a resolved `Scope` — a stored
      persona wins only if the person still holds it.
    * `from_user/1` runs no query. `UserAuth.signed_in_path/1` calls it from
      inside `UserLive.Registration`'s `mount/3`, where the personas do not
      exist yet: they are created asynchronously by the outbox handlers off
      `user_registered`. Resolving there would both add queries to mount and
      send every brand-new provider to the parent dashboard.
  """
  use ExUnit.Case, async: true

  alias KlassHero.Accounts.Scope
  alias KlassHero.Accounts.Types.UserRole
  alias KlassHero.Accounts.User
  alias KlassHeroWeb.Persona

  # A Scope carrying exactly the personas named. resolve/1 reads presence of the
  # profile structs, so a bare marker map is enough — no DB, no fixtures.
  defp scope(personas, active_persona \\ nil) do
    %Scope{
      user: %User{id: "u1", active_persona: active_persona},
      roles: personas,
      parent: if(:parent in personas, do: %{id: "p1"}),
      provider: if(:provider in personas, do: %{id: "pv1"}),
      staff_member: if(:staff in personas, do: %{id: "s1"})
    }
  end

  describe "known/0" do
    test "is the Accounts vocabulary, not a second copy of it" do
      assert Persona.known() == UserRole.valid_roles()
    end
  end

  describe "validate/1" do
    test "accepts every known persona as an atom or a string" do
      for persona <- Persona.known() do
        assert Persona.validate(persona) == persona
        assert Persona.validate(Atom.to_string(persona)) == persona
      end
    end

    # Coerces rather than raises: every caller receives this from untrusted input
    # — a path param, a session written by an older release, a column holding a
    # since-retired value. Never String.to_atom/1, which would leak the atom table.
    test "coerces anything else to nil" do
      for input <- ["admin", "PARENT", "", nil, :staff_provider, 42, %{}] do
        assert Persona.validate(input) == nil, "#{inspect(input)} was accepted"
      end
    end
  end

  describe "resolve/1 — no stored preference" do
    @precedence [
      {[:parent], :parent},
      {[:provider], :provider},
      {[:staff], :staff},
      {[:parent, :provider], :provider},
      {[:parent, :staff], :staff},
      {[:provider, :staff], :provider},
      {[:parent, :provider, :staff], :provider},
      {[], :parent}
    ]

    test "falls back to provider > staff > parent, exactly as before" do
      for {personas, expected} <- @precedence do
        assert Persona.resolve(scope(personas)) == expected,
               "#{inspect(personas)} should default to #{expected}"
      end
    end
  end

  describe "resolve/1 — stored preference" do
    test "honours a stored persona the person actually holds" do
      assert Persona.resolve(scope([:parent, :provider], :parent)) == :parent
      assert Persona.resolve(scope([:parent, :provider], :provider)) == :provider
      assert Persona.resolve(scope([:parent, :staff], :parent)) == :parent
    end

    # The whole point of ADR-0005's "authorization authority is persona
    # existence": a stored value is a preference and can never conjure a persona.
    test "ignores a stored persona the person no longer holds" do
      assert Persona.resolve(scope([:parent], :provider)) == :parent
      assert Persona.resolve(scope([:provider], :parent)) == :provider
      assert Persona.resolve(scope([:provider, :staff], :parent)) == :provider
    end

    test "ignores a stored persona on a scope holding nothing yet" do
      assert Persona.resolve(scope([], :provider)) == :parent
    end
  end

  describe "resolve/1 — no user" do
    test "defaults to parent for an anonymous scope" do
      assert Persona.resolve(%Scope{}) == :parent
    end
  end

  describe "from_user/1 — the no-query path" do
    test "prefers a stored persona" do
      user = %User{active_persona: :parent, intended_roles: [:parent, :provider]}
      assert Persona.from_user(user) == :parent
    end

    # Personas are created asynchronously off `user_registered`, so at the moment
    # registration redirects there is no ProviderProfile row to resolve against.
    # intended_roles is the eventual-consistency bridge CONTEXT.md names.
    test "falls back to the intended_roles landing hint when nothing is stored" do
      assert Persona.from_user(%User{intended_roles: [:provider]}) == :provider
      assert Persona.from_user(%User{intended_roles: [:staff]}) == :staff
      assert Persona.from_user(%User{intended_roles: [:parent, :provider]}) == :provider
    end

    test "defaults to parent with neither a preference nor a hint" do
      assert Persona.from_user(%User{intended_roles: []}) == :parent
      assert Persona.from_user(%User{intended_roles: nil}) == :parent
      assert Persona.from_user(nil) == :parent
    end

    # A stored persona missing from intended_roles is not evidence of anything —
    # intended_roles is appended whenever a persona is gained (ADR-0005), so the
    # two only disagree while the outbox is catching up. Trust the explicit choice.
    test "trusts the stored persona over a lagging hint" do
      assert Persona.from_user(%User{active_persona: :parent, intended_roles: [:provider]}) ==
               :parent
    end
  end

  describe "available/1" do
    test "lists only personas actually held, in nav order" do
      assert Persona.available(scope([:parent, :provider, :staff])) ==
               [:parent, :provider, :staff]

      assert Persona.available(scope([:provider])) == [:provider]
      assert Persona.available(scope([])) == []
      assert Persona.available(%Scope{}) == []
    end
  end

  describe "path/2" do
    @paths [
      {:parent, :dashboard, "/dashboard"},
      {:provider, :dashboard, "/provider/dashboard"},
      {:staff, :dashboard, "/staff/dashboard"},
      {:parent, :messages, "/messages"},
      {:provider, :messages, "/provider/messages"},
      {:staff, :messages, "/staff/messages"}
    ]

    test "maps a persona and a page to the one URL that serves it" do
      for {persona, page, expected} <- @paths do
        assert Persona.path(persona, page) == expected,
               "#{persona}/#{page} should be #{expected}"
      end
    end
  end

  describe "label/1" do
    test "every known persona has a non-empty label" do
      for persona <- Persona.known() do
        label = Persona.label(persona)
        assert is_binary(label) and label != "", "#{persona} has no label"
      end
    end
  end
end
