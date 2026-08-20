defmodule KlassHero.Accounts.UpgradeToParentTest do
  @moduledoc """
  The mirror of `upgrade_to_provider/1` for the other direction (#899).

  A provider could never gain a parent persona: nothing in Accounts created one,
  and the two flows that hit the gap — starting a booking, opening Children —
  redirected to a settings page that could not grant it either.

  Unlike provider-hood there is no profile to fill in. `create_parent_profile/1`
  needs only the identity, so this is a one-click grant with no completion flow
  behind it.
  """
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts
  alias KlassHero.Accounts.User
  alias KlassHero.Family

  defp reload_roles(user_id), do: Repo.get!(User, user_id).intended_roles

  describe "upgrade_to_parent/1 (happy path)" do
    test "creates a parent profile for the existing identity and appends :parent" do
      user = user_fixture(intended_roles: [:provider])

      assert {:ok, updated} = Accounts.upgrade_to_parent(user)

      assert updated.intended_roles == [:provider, :parent]
      assert reload_roles(user.id) == [:provider, :parent]

      assert {:ok, parent} = Family.get_parent_by_identity(user.id)
      assert parent.identity_id == user.id
    end
  end

  describe "upgrade_to_parent/1 (already a parent)" do
    test "returns :already_parent and performs no writes" do
      user = user_fixture(intended_roles: [:provider])
      {:ok, existing} = Family.create_parent_profile(%{identity_id: user.id})

      assert {:error, :already_parent} = Accounts.upgrade_to_parent(user)

      # No role granted, no second profile, existing profile untouched.
      assert reload_roles(user.id) == [:provider]
      assert {:ok, parent} = Family.get_parent_by_identity(user.id)
      assert parent.id == existing.id
    end
  end

  describe "upgrade_to_parent/1 (stale session struct)" do
    # The lost-update class PersonaGrant exists to prevent (#968): another tab
    # grants a role after this session's struct was loaded, and writing the
    # stale array back would silently drop it.
    test "a role granted after the struct was loaded survives the upgrade" do
      user = user_fixture(intended_roles: [:provider])

      {1, _} =
        Repo.update_all(from(u in User, where: u.id == ^user.id),
          set: [intended_roles: ["provider", "staff"]]
        )

      assert {:ok, updated} = Accounts.upgrade_to_parent(user)

      assert :staff in updated.intended_roles
      assert :parent in updated.intended_roles
      assert :staff in reload_roles(user.id)
    end
  end
end
