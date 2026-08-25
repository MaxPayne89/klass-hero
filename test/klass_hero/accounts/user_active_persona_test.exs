defmodule KlassHero.Accounts.UserActivePersonaTest do
  @moduledoc """
  The changeset that decides whether a remembered persona can be stored.

  Two things separate it from `locale_changeset/2`, its nearest sibling. It is
  nullable, because `nil` is a real answer — "never chose" — that the read path
  treats as today's provider > staff > parent precedence. And storing a persona
  is not the same as holding one: this only guards the vocabulary, while
  `Scope.parent?/1` and friends stay the sole authority for whether the persona
  exists (ADR-0005). Assertions derive from `UserRole.valid_roles/0` rather than
  naming the three atoms again (#1227).
  """
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias KlassHero.Accounts.User
  alias KlassHero.Accounts.UserRole

  describe "active_persona_changeset/2" do
    test "accepts every persona the app claims to know" do
      for persona <- UserRole.valid_roles() do
        changeset = User.active_persona_changeset(%User{}, %{active_persona: persona})

        assert changeset.valid?,
               "#{persona} is in UserRole.valid_roles/0 but the changeset rejects it: " <>
                 inspect(changeset.errors)

        assert Changeset.get_field(changeset, :active_persona) == persona
      end
    end

    test "casts the string form a controller param arrives as" do
      for persona <- UserRole.valid_roles() do
        changeset =
          User.active_persona_changeset(%User{}, %{active_persona: Atom.to_string(persona)})

        assert changeset.valid?
        assert Changeset.get_field(changeset, :active_persona) == persona
      end
    end

    # Not plausible-looking near-misses by accident: :admin and :guardian are real
    # words in this domain (CONTEXT.md) that are deliberately NOT personas, so a
    # future rename that promoted either would have to break this test first.
    @never_personas [:admin, :guardian, :staff_provider, "PARENT", "not-a-persona"]

    test "rejects anything outside that set" do
      assert Enum.all?(@never_personas, &(&1 not in UserRole.valid_roles())),
             "fixture overlaps UserRole.valid_roles/0 — this test would be vacuous"

      for persona <- @never_personas do
        changeset =
          User.active_persona_changeset(%User{active_persona: :parent}, %{
            active_persona: persona
          })

        refute changeset.valid?, "#{inspect(persona)} was accepted as a persona"
        assert Keyword.has_key?(changeset.errors, :active_persona)
      end
    end

    # nil is not an error here, unlike locale: it is how a user says "no
    # preference", and it is what every pre-existing row holds.
    test "accepts nil as the absence of a preference" do
      changeset = User.active_persona_changeset(%User{active_persona: :provider}, %{active_persona: nil})

      assert changeset.valid?
      assert Changeset.get_field(changeset, :active_persona) == nil
    end

    # The subject is a schema default, which is application code the check cannot see:
    # a struct literal is not a function call.
    # credo:disable-for-next-line Jump.CredoChecks.VacuousTest
    test "the schema default is no preference" do
      assert %User{}.active_persona == nil
    end
  end
end
