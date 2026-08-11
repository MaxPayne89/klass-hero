defmodule KlassHero.Provider.Staff.AcceptStaffInvitationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.EventTestHelper
  import KlassHero.Factory
  import KlassHero.ProviderFixtures

  alias KlassHero.Provider
  alias KlassHero.Provider.StaffMember

  setup do
    setup_test_integration_events()
    :ok
  end

  defp sent_staff(provider, opts \\ []) do
    staff_member_fixture(
      Keyword.merge(
        [
          provider_id: provider.id,
          email: "invited-#{System.unique_integer([:positive])}@example.com",
          invitation_status: :sent,
          invitation_token_hash: :crypto.hash(:sha256, "tok-#{System.unique_integer([:positive])}"),
          invitation_sent_at: DateTime.utc_now()
        ],
        opts
      )
    )
  end

  describe "execute/2" do
    test "links the user and transitions a sent invitation to accepted" do
      provider = provider_profile_fixture()
      staff = sent_staff(provider)
      user_id = user_fixture().id

      assert {:ok, accepted} = Provider.accept_staff_invitation(staff, user_id)
      assert accepted.invitation_status == :accepted
      assert accepted.user_id == user_id
    end

    test "is idempotent — re-accepting by the same user is a no-op success" do
      provider = provider_profile_fixture()
      staff = sent_staff(provider)
      user_id = user_fixture().id

      assert {:ok, accepted} = Provider.accept_staff_invitation(staff, user_id)
      assert {:ok, again} = Provider.accept_staff_invitation(accepted, user_id)

      assert again.invitation_status == :accepted
      assert again.user_id == user_id
    end

    test "supports multi-employer — same user accepts at two different providers" do
      user_id = user_fixture().id
      staff_a = sent_staff(provider_profile_fixture())
      staff_b = sent_staff(provider_profile_fixture())

      assert {:ok, a} = Provider.accept_staff_invitation(staff_a, user_id)
      assert {:ok, b} = Provider.accept_staff_invitation(staff_b, user_id)

      assert a.user_id == user_id
      assert b.user_id == user_id
      assert a.provider_id != b.provider_id
    end

    test "exposed via the Provider facade" do
      provider = provider_profile_fixture()
      staff = sent_staff(provider)
      user_id = user_fixture().id

      assert {:ok, accepted} = Provider.accept_staff_invitation(staff, user_id)
      assert accepted.invitation_status == :accepted
    end

    test "accepting becomes the selected staff context, beating a prior switcher selection" do
      # Regression (#969 switcher review finding 1): selection ordering ranks
      # last_selected_at above inserted_at, so without a bump on accept the
      # freshly joined employer would lose to any previously selected one and
      # the post-accept redirect would land on the OLD employer's dashboard.
      user = user_fixture(intended_roles: [:staff])
      old_employer = provider_profile_fixture()

      staff_member_fixture(%{
        provider_id: old_employer.id,
        user_id: user.id,
        invitation_status: :accepted,
        last_selected_at: ~U[2026-06-01 09:00:00Z]
      })

      new_employer = provider_profile_fixture()
      invite = sent_staff(new_employer)

      assert {:ok, accepted} = Provider.accept_staff_invitation(invite, user.id)

      assert {:ok, resolved} = Provider.get_active_staff_member_by_user(user.id)
      assert resolved.id == accepted.id
      assert resolved.provider_id == new_employer.id
    end

    test "re-fetches fresh state — a stale :sent struct whose DB row is :expired cannot resurrect" do
      provider = provider_profile_fixture()
      stale = sent_staff(provider)
      user_id = user_fixture().id

      # The DB row expires after the caller captured the :sent struct.
      assert {:ok, _} = Provider.expire_staff_invitation(stale)
      assert stale.invitation_status == :sent

      # Accepting with the stale :sent struct must read the fresh :expired state and
      # refuse — not blindly transition the in-memory :sent → :accepted (resurrection).
      assert {:error, :invalid_invitation_transition} =
               Provider.accept_staff_invitation(stale, user_id)

      assert {:ok, db} = Provider.get_staff_member(stale.id)
      assert db.invitation_status == :expired
      assert is_nil(db.user_id)
    end
  end

  # A program assigned before the invite was claimed emitted a
  # staff_assigned_to_program carrying a nil staff_user_id, which Messaging
  # skipped. Acceptance is the moment those assignments become addressable, so
  # it replays them — otherwise the staff member is cut out of that program's
  # messaging permanently (#1312).
  describe "replaying assignments made before the invite was claimed" do
    test "stages one staff_assigned_to_program per active assignment, carrying the linked user" do
      provider = provider_profile_fixture()
      staff = sent_staff(provider)
      user_id = user_fixture().id

      program_a = insert(:program_schema, provider_id: provider.id)
      program_b = insert(:program_schema, provider_id: provider.id)

      for program <- [program_a, program_b] do
        insert(:program_staff_assignment_schema,
          provider_id: provider.id,
          program_id: program.id,
          staff_member_id: staff.id
        )
      end

      assert {:ok, _accepted} = Provider.accept_staff_invitation(staff, user_id)

      for program <- [program_a, program_b] do
        assert_integration_event_published(:staff_assigned_to_program, %{
          provider_id: provider.id,
          program_id: program.id,
          staff_member_id: staff.id,
          staff_user_id: user_id
        })
      end

      assert length(assignment_events()) == 2
    end

    @replay_cases [
      {"no assignment at all", nil, 0},
      {"an assignment already removed", :unassigned_program_staff_assignment_schema, 0},
      {"a standing assignment", :program_staff_assignment_schema, 1}
    ]

    test "only standing assignments replay" do
      for {label, factory, expected} <- @replay_cases do
        provider = provider_profile_fixture()
        staff = sent_staff(provider)
        user_id = user_fixture().id

        if factory do
          insert(factory,
            provider_id: provider.id,
            program_id: insert(:program_schema, provider_id: provider.id).id,
            staff_member_id: staff.id
          )
        end

        clear_integration_events()
        assert {:ok, _accepted} = Provider.accept_staff_invitation(staff, user_id)

        assert length(assignment_events()) == expected,
               "with #{label}, expected #{expected} replayed event(s), got #{length(assignment_events())}"
      end
    end

    test "re-accepting does not replay — the short circuit stages nothing" do
      provider = provider_profile_fixture()
      staff = sent_staff(provider)
      user_id = user_fixture().id

      insert(:program_staff_assignment_schema,
        provider_id: provider.id,
        program_id: insert(:program_schema, provider_id: provider.id).id,
        staff_member_id: staff.id
      )

      assert {:ok, accepted} = Provider.accept_staff_invitation(staff, user_id)
      assert length(assignment_events()) == 1

      clear_integration_events()
      assert {:ok, _again} = Provider.accept_staff_invitation(accepted, user_id)
      assert assignment_events() == []
    end

    test "a failed selection bump rolls the whole acceptance back" do
      # Staging the replay puts acceptance in a transaction, so the link no
      # longer survives a later step failing. Half-accepted — user linked but
      # never selectable — is not a state worth keeping.
      provider = provider_profile_fixture()
      staff = sent_staff(provider)
      user_id = user_fixture().id

      Repo.update_all(from(s in StaffMember, where: s.id == ^staff.id), set: [active: false])

      assert {:error, :not_staffed} = Provider.accept_staff_invitation(staff, user_id)

      assert {:ok, db} = Provider.get_staff_member(staff.id)
      assert is_nil(db.user_id)
      assert db.invitation_status == :sent
      assert assignment_events() == []
    end
  end

  defp assignment_events do
    Enum.filter(get_published_integration_events(), &(&1.event_type == :staff_assigned_to_program))
  end
end
