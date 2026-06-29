defmodule KlassHero.Accounts.AddSelfAsStaffTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.ProviderFixtures

  alias KlassHero.Accounts
  alias KlassHero.Accounts.User
  alias KlassHero.Provider

  @staff_attrs %{first_name: "Max", last_name: "Founder", role: "Head Coach"}

  defp reload_roles(user_id), do: Repo.get!(User, user_id).intended_roles

  defp own_staff_row(provider_id, user_id) do
    {:ok, members} = Provider.list_staff_members(provider_id)
    Enum.find(members, &(&1.user_id == user_id))
  end

  describe "add_self_as_staff/2 (happy path)" do
    test "creates a linked, accepted staff row under the own business and appends :staff" do
      user = user_fixture(intended_roles: [:provider])
      provider = provider_profile_fixture(identity_id: user.id)

      assert {:ok, updated, staff} = Accounts.add_self_as_staff(user, @staff_attrs)

      assert updated.intended_roles == [:provider, :staff]
      assert reload_roles(user.id) == [:provider, :staff]

      assert staff.provider_id == provider.id
      assert staff.user_id == user.id
      assert staff.invitation_status == :accepted
      assert is_nil(staff.invitation_token_hash)
      assert staff.first_name == "Max"
      assert own_staff_row(provider.id, user.id).id == staff.id
    end

    test "the self row always carries the account email, whatever was submitted" do
      user = user_fixture(intended_roles: [:provider])
      provider_profile_fixture(identity_id: user.id)

      tampered = Map.put(@staff_attrs, :email, "someone-else@example.com")

      assert {:ok, _updated, staff} = Accounts.add_self_as_staff(user, tampered)

      assert staff.email == user.email
    end
  end

  describe "add_self_as_staff/2 (guards)" do
    test "a user without a provider profile gets :not_a_provider and no writes" do
      user = user_fixture(intended_roles: [:parent])

      assert {:error, :not_a_provider} = Accounts.add_self_as_staff(user, @staff_attrs)

      assert reload_roles(user.id) == [:parent]
    end

    test "already self-staffed passes :already_staffed through, roles unchanged" do
      user = user_fixture(intended_roles: [:provider])
      provider = provider_profile_fixture(identity_id: user.id)

      assert {:ok, _, _} = Accounts.add_self_as_staff(user, @staff_attrs)
      assert {:error, :already_staffed} = Accounts.add_self_as_staff(user, @staff_attrs)

      assert {:ok, [_only_one]} = Provider.list_staff_members(provider.id)
    end
  end

  describe "add_self_as_staff/2 (stale session struct)" do
    test "a role granted after the struct was loaded survives" do
      user = user_fixture(intended_roles: [:provider])
      provider_profile_fixture(identity_id: user.id)

      {1, _} =
        Repo.update_all(from(u in User, where: u.id == ^user.id),
          set: [intended_roles: ["provider", "parent"]]
        )

      assert {:ok, updated, _staff} = Accounts.add_self_as_staff(user, @staff_attrs)

      assert :parent in updated.intended_roles
      assert :staff in updated.intended_roles
    end
  end
end
