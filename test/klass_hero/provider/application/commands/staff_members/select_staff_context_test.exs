defmodule KlassHero.Provider.Application.Commands.StaffMembers.SelectStaffContextTest do
  @moduledoc """
  Tests for Provider.select_staff_context/2 (#969 staff-context switcher):
  remembering which employment a multi-employer staff user works in.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider
  alias KlassHero.ProviderFixtures

  describe "select_staff_context/2" do
    test "selecting an employment makes it the scope-resolved row" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      employer = ProviderFixtures.provider_profile_fixture()
      own_business = ProviderFixtures.provider_profile_fixture(%{identity_id: user.id})

      ProviderFixtures.staff_member_fixture(%{provider_id: employer.id, user_id: user.id})

      own_row =
        ProviderFixtures.staff_member_fixture(%{provider_id: own_business.id, user_id: user.id})

      # Employer-first default before any selection.
      assert {:ok, before_selection} = Provider.get_active_staff_member_by_user(user.id)
      assert before_selection.provider_id == employer.id

      assert {:ok, :selected} = Provider.select_staff_context(user.id, own_business.id)

      assert {:ok, after_selection} = Provider.get_active_staff_member_by_user(user.id)
      assert after_selection.id == own_row.id
    end

    test "selecting again moves the selection back" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      employer_a = ProviderFixtures.provider_profile_fixture()
      employer_b = ProviderFixtures.provider_profile_fixture()

      ProviderFixtures.staff_member_fixture(%{provider_id: employer_a.id, user_id: user.id})
      ProviderFixtures.staff_member_fixture(%{provider_id: employer_b.id, user_id: user.id})

      assert {:ok, :selected} = Provider.select_staff_context(user.id, employer_b.id)
      assert {:ok, :selected} = Provider.select_staff_context(user.id, employer_a.id)

      assert {:ok, current} = Provider.get_active_staff_member_by_user(user.id)
      assert current.provider_id == employer_a.id
    end

    test "returns :not_staffed when the user has no active row at that provider" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      employer = ProviderFixtures.provider_profile_fixture()
      unrelated = ProviderFixtures.provider_profile_fixture()

      ProviderFixtures.staff_member_fixture(%{provider_id: employer.id, user_id: user.id})

      assert {:error, :not_staffed} = Provider.select_staff_context(user.id, unrelated.id)
    end

    test "returns :not_staffed when the row at that provider is inactive" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      former = ProviderFixtures.provider_profile_fixture()

      ProviderFixtures.staff_member_fixture(%{
        provider_id: former.id,
        user_id: user.id,
        active: false
      })

      assert {:error, :not_staffed} = Provider.select_staff_context(user.id, former.id)
    end

    test "does not touch other users' rows at the same provider" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      colleague = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      employer = ProviderFixtures.provider_profile_fixture()

      ProviderFixtures.staff_member_fixture(%{provider_id: employer.id, user_id: user.id})

      colleague_row =
        ProviderFixtures.staff_member_fixture(%{provider_id: employer.id, user_id: colleague.id})

      assert {:ok, :selected} = Provider.select_staff_context(user.id, employer.id)

      colleague_selected_at =
        Repo.one!(
          from(s in "staff_members",
            where: s.id == type(^colleague_row.id, :binary_id),
            select: s.last_selected_at
          )
        )

      assert is_nil(colleague_selected_at)
    end
  end
end
