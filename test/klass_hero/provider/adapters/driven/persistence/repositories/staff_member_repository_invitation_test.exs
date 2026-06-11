defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.StaffMemberRepositoryInvitationTest do
  @moduledoc """
  Tests for invitation-related repository functions on StaffMemberRepository.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.StaffMemberRepository
  alias KlassHero.Provider.Domain.Models.StaffMember
  alias KlassHero.ProviderFixtures

  describe "get_by_token_hash/1" do
    test "returns staff member when token hash matches and invitation_status is sent" do
      token_hash = :crypto.strong_rand_bytes(32)

      staff =
        ProviderFixtures.staff_member_fixture(%{
          invitation_status: :sent,
          invitation_token_hash: token_hash,
          invitation_sent_at: DateTime.utc_now()
        })

      assert {:ok, %StaffMember{} = found} = StaffMemberRepository.get_by_token_hash(token_hash)
      assert found.id == staff.id
      assert found.invitation_status == :sent
      assert found.invitation_token_hash == token_hash
    end

    test "returns :not_found when token hash does not match" do
      token_hash = :crypto.strong_rand_bytes(32)
      other_hash = :crypto.strong_rand_bytes(32)

      ProviderFixtures.staff_member_fixture(%{
        invitation_status: :sent,
        invitation_token_hash: token_hash,
        invitation_sent_at: DateTime.utc_now()
      })

      assert {:error, :not_found} = StaffMemberRepository.get_by_token_hash(other_hash)
    end

    test "returns :not_found when invitation_status is not sent" do
      token_hash = :crypto.strong_rand_bytes(32)

      ProviderFixtures.staff_member_fixture(%{
        invitation_status: :pending,
        invitation_token_hash: token_hash
      })

      assert {:error, :not_found} = StaffMemberRepository.get_by_token_hash(token_hash)
    end

    test "returns :not_found when no staff member exists with that token hash" do
      token_hash = :crypto.strong_rand_bytes(32)

      assert {:error, :not_found} = StaffMemberRepository.get_by_token_hash(token_hash)
    end
  end

  describe "get_active_by_user/1" do
    test "returns staff member when user_id matches and active is true" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      staff =
        ProviderFixtures.staff_member_fixture(%{
          user_id: user.id,
          active: true
        })

      assert {:ok, %StaffMember{} = found} = StaffMemberRepository.get_active_by_user(user.id)
      assert found.id == staff.id
      assert found.user_id == user.id
      assert found.active == true
    end

    test "returns :not_found when user_id does not match" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      other_user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      ProviderFixtures.staff_member_fixture(%{
        user_id: user.id,
        active: true
      })

      assert {:error, :not_found} = StaffMemberRepository.get_active_by_user(other_user.id)
    end

    test "returns :not_found when staff member is inactive" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      ProviderFixtures.staff_member_fixture(%{
        user_id: user.id,
        active: false
      })

      assert {:error, :not_found} = StaffMemberRepository.get_active_by_user(user.id)
    end

    test "returns :not_found when no staff member exists for user_id" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      assert {:error, :not_found} = StaffMemberRepository.get_active_by_user(user.id)
    end
  end

  describe "get_active_by_user/1 selection ordering (#969 staff-context switcher)" do
    # Selection rule: last_selected_at desc (nulls last), then employer rows
    # before own-business rows, then newest. "Own business" = the staff row's
    # provider has identity_id == user_id (founder self-staffed via #969).

    test "employer row beats a NEWER own-business row when nothing was ever selected" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      employer = ProviderFixtures.provider_profile_fixture()
      own_business = ProviderFixtures.provider_profile_fixture(%{identity_id: user.id})

      employer_row =
        ProviderFixtures.staff_member_fixture(%{
          provider_id: employer.id,
          user_id: user.id,
          inserted_at: ~U[2026-01-01 10:00:00Z]
        })

      ProviderFixtures.staff_member_fixture(%{
        provider_id: own_business.id,
        user_id: user.id,
        inserted_at: ~U[2026-06-01 10:00:00Z]
      })

      assert {:ok, found} = StaffMemberRepository.get_active_by_user(user.id)
      assert found.id == employer_row.id
    end

    test "a selected own-business row beats the employer-first default" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      employer = ProviderFixtures.provider_profile_fixture()
      own_business = ProviderFixtures.provider_profile_fixture(%{identity_id: user.id})

      ProviderFixtures.staff_member_fixture(%{provider_id: employer.id, user_id: user.id})

      own_row =
        ProviderFixtures.staff_member_fixture(%{
          provider_id: own_business.id,
          user_id: user.id,
          last_selected_at: ~U[2026-06-10 09:00:00Z]
        })

      assert {:ok, found} = StaffMemberRepository.get_active_by_user(user.id)
      assert found.id == own_row.id
    end

    test "the most recently selected row wins when several were selected" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      employer_a = ProviderFixtures.provider_profile_fixture()
      employer_b = ProviderFixtures.provider_profile_fixture()

      ProviderFixtures.staff_member_fixture(%{
        provider_id: employer_a.id,
        user_id: user.id,
        last_selected_at: ~U[2026-06-01 09:00:00Z]
      })

      row_b =
        ProviderFixtures.staff_member_fixture(%{
          provider_id: employer_b.id,
          user_id: user.id,
          last_selected_at: ~U[2026-06-10 09:00:00Z]
        })

      assert {:ok, found} = StaffMemberRepository.get_active_by_user(user.id)
      assert found.id == row_b.id
    end

    test "newest row wins among never-selected employer rows" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      employer_a = ProviderFixtures.provider_profile_fixture()
      employer_b = ProviderFixtures.provider_profile_fixture()

      ProviderFixtures.staff_member_fixture(%{
        provider_id: employer_a.id,
        user_id: user.id,
        inserted_at: ~U[2026-01-01 10:00:00Z]
      })

      row_b =
        ProviderFixtures.staff_member_fixture(%{
          provider_id: employer_b.id,
          user_id: user.id,
          inserted_at: ~U[2026-03-01 10:00:00Z]
        })

      assert {:ok, found} = StaffMemberRepository.get_active_by_user(user.id)
      assert found.id == row_b.id
    end

    test "an own-business row is still returned when it is the only active row" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      own_business = ProviderFixtures.provider_profile_fixture(%{identity_id: user.id})

      own_row =
        ProviderFixtures.staff_member_fixture(%{provider_id: own_business.id, user_id: user.id})

      assert {:ok, found} = StaffMemberRepository.get_active_by_user(user.id)
      assert found.id == own_row.id
    end

    test "fully tied rows resolve deterministically and agree with the memberships head" do
      # staff_members timestamps are second-precision: two invite-accepts in the
      # same second tie on every ordering key unless a unique tiebreaker exists.
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      employer_a = ProviderFixtures.provider_profile_fixture()
      employer_b = ProviderFixtures.provider_profile_fixture()
      tied_at = ~U[2026-03-01 10:00:00Z]

      for employer <- [employer_a, employer_b] do
        ProviderFixtures.staff_member_fixture(%{
          provider_id: employer.id,
          user_id: user.id,
          inserted_at: tied_at
        })
      end

      results =
        for _run <- 1..3 do
          {:ok, found} = StaffMemberRepository.get_active_by_user(user.id)
          {:ok, [head | _]} = StaffMemberRepository.list_active_memberships_by_user(user.id)
          {found.id, head.staff_member_id}
        end

      assert [{resolved, resolved}] = Enum.uniq(results),
             "limit-1 row and memberships head must agree and be stable: #{inspect(results)}"
    end
  end
end
