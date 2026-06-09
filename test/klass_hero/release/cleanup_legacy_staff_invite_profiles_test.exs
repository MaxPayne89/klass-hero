defmodule KlassHero.Release.CleanupLegacyStaffInviteProfilesTest do
  @moduledoc """
  Tests the #966 blanket-cleanup transform (ADR-0005): delete every ProviderProfile
  originated from a staff invite and strip `:provider` from those users, leaving
  `:staff` (and any other roles) intact.

  The migration's `up/0` calls `run/1` directly, so these tests exercise the exact
  code the migration runs — not a duplicate of its SQL.
  """
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.ProviderFixtures

  alias KlassHero.Accounts.User
  alias KlassHero.Provider
  alias KlassHero.Release.CleanupLegacyStaffInviteProfiles

  defp roles(user_id), do: Repo.get!(User, user_id).intended_roles

  describe "run/1" do
    test "deletes a staff-invite profile and strips :provider, keeping :staff" do
      user = user_fixture(intended_roles: [:staff, :provider])
      _profile = provider_profile_fixture(identity_id: user.id, originated_from: "staff_invite")

      assert {:ok, _counts} = CleanupLegacyStaffInviteProfiles.run(Repo)

      refute Provider.has_provider_profile?(to_string(user.id))
      assert roles(user.id) == [:staff]
    end

    test "strips only :provider, leaving :parent and :staff intact" do
      user = user_fixture(intended_roles: [:parent, :staff, :provider])
      _profile = provider_profile_fixture(identity_id: user.id, originated_from: "staff_invite")

      assert {:ok, _counts} = CleanupLegacyStaffInviteProfiles.run(Repo)

      assert roles(user.id) == [:parent, :staff]
    end

    test "leaves direct providers and their :provider role untouched" do
      user = user_fixture(intended_roles: [:provider])
      profile = provider_profile_fixture(identity_id: user.id, originated_from: "direct")

      assert {:ok, %{profiles_deleted: 0}} = CleanupLegacyStaffInviteProfiles.run(Repo)

      assert Provider.has_provider_profile?(to_string(user.id))
      assert roles(user.id) == [:provider]
      assert {:ok, _} = Provider.get_provider_by_identity(to_string(profile.identity_id))
    end

    test "is idempotent — a second run is a no-op" do
      user = user_fixture(intended_roles: [:staff, :provider])
      _profile = provider_profile_fixture(identity_id: user.id, originated_from: "staff_invite")

      assert {:ok, %{profiles_deleted: 1, users_updated: 1}} =
               CleanupLegacyStaffInviteProfiles.run(Repo)

      assert {:ok, %{profiles_deleted: 0, users_updated: 0}} =
               CleanupLegacyStaffInviteProfiles.run(Repo)

      assert roles(user.id) == [:staff]
    end

    test "returns affected counts for the HITL gate" do
      user = user_fixture(intended_roles: [:staff, :provider])
      _profile = provider_profile_fixture(identity_id: user.id, originated_from: "staff_invite")

      assert {:ok, %{profiles_deleted: 1, users_updated: 1}} =
               CleanupLegacyStaffInviteProfiles.run(Repo)
    end
  end
end
