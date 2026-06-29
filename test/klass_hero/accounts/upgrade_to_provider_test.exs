defmodule KlassHero.Accounts.UpgradeToProviderTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.ProviderFixtures

  alias KlassHero.Accounts
  alias KlassHero.Accounts.User
  alias KlassHero.Provider

  defp reload_roles(user_id), do: Repo.get!(User, user_id).intended_roles

  describe "upgrade_to_provider/1 (happy path)" do
    test "creates a draft provider profile for the existing identity and appends :provider" do
      user = user_fixture(intended_roles: [:staff])

      assert {:ok, updated} = Accounts.upgrade_to_provider(user)

      assert updated.intended_roles == [:staff, :provider]
      assert reload_roles(user.id) == [:staff, :provider]

      assert {:ok, profile} = Provider.get_provider_by_identity(user.id)
      assert profile.profile_status == :draft
      assert profile.business_name == user.name
      assert profile.business_owner_email == user.email
    end
  end

  describe "upgrade_to_provider/1 (already a provider)" do
    test "returns :already_provider and performs no writes" do
      user = user_fixture(intended_roles: [:staff])
      existing = provider_profile_fixture(identity_id: user.id)

      assert {:error, :already_provider} = Accounts.upgrade_to_provider(user)

      # No role granted, no second profile, existing profile untouched.
      assert reload_roles(user.id) == [:staff]
      assert {:ok, profile} = Provider.get_provider_by_identity(user.id)
      assert profile.id == existing.id
      assert profile.business_name == existing.business_name
    end
  end

  describe "upgrade_to_provider/1 (stale session struct)" do
    test "a role granted after the struct was loaded survives the upgrade" do
      user = user_fixture(intended_roles: [:staff])

      # Another flow (e.g. a second tab) grants :parent after this session's
      # struct was loaded — the command must not write the stale array back.
      {1, _} =
        Repo.update_all(from(u in User, where: u.id == ^user.id),
          set: [intended_roles: ["staff", "parent"]]
        )

      assert {:ok, updated} = Accounts.upgrade_to_provider(user)

      assert :parent in updated.intended_roles
      assert :provider in updated.intended_roles
      assert :parent in reload_roles(user.id)
    end
  end

  # No atomicity test: there is no constructible in-transaction failure.
  # `users.name` is NOT NULL (2-100 chars), so the derived business_name always
  # passes ProviderProfile validation, and appending the valid `:provider` atom
  # cannot fail. The transaction in the command exists purely as the race
  # backstop behind `providers_identity_id_index` (duplicate-identity behaviour
  # is covered in create_provider_profile_test.exs). For the same reason the
  # race-loser mapping ({:error, :duplicate_resource} -> :already_provider)
  # is untestable through the public API: the pre-check shadows the constraint
  # path in any single-process test.
end
