defmodule KlassHero.Messaging.AddAssignedStaffTest do
  use KlassHero.DataCase, async: false

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.AddAssignedStaff
  alias KlassHero.Messaging.Conversation
  alias KlassHero.ProviderFixtures
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.Event

  setup do
    setup_test_integration_events()
    :ok
  end

  describe "execute/3 — events-as-data contract" do
    test "returns {:ok, {added_ids, [Event]}} and does NOT dispatch the event itself" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      owner = AccountsFixtures.user_fixture()
      staff_a = AccountsFixtures.user_fixture()
      staff_b = AccountsFixtures.user_fixture()

      ProviderFixtures.assign_active_staff(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff_a.id
      })

      ProviderFixtures.assign_active_staff(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff_b.id
      })

      conversation_id = Ecto.UUID.generate()

      Repo.insert!(%Conversation{
        id: conversation_id,
        type: :direct,
        provider_id: provider.id,
        program_id: program.id
      })

      assert {:ok, {:ok, {added_ids, events}}} =
               Repo.transaction(fn ->
                 AddAssignedStaff.execute(conversation_id, program.id, owner.id)
               end)

      assert Enum.sort(added_ids) == Enum.sort([staff_a.id, staff_b.id])
      assert KlassHero.Messaging.participant?(conversation_id, staff_a.id)
      assert KlassHero.Messaging.participant?(conversation_id, staff_b.id)

      assert [%Event{} = event] = events
      assert event.event_type == :participant_added
      assert event.entity_id == conversation_id
      assert event.entity_type == :conversation
      assert Enum.sort(event.payload.participant_user_ids) == Enum.sort([staff_a.id, staff_b.id])
      assert event.payload.source == :initial_staff

      # Critical: the command must NOT dispatch the event itself —
      # post-commit dispatch is the caller's responsibility so the projection
      # can read-your-own-writes after Repo.transaction commits.
      refute Enum.any?(
               get_published_integration_events(),
               &(&1.event_type == :participant_added)
             )
    end

    test "excludes the owner from participant additions and from event payload" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      owner = AccountsFixtures.user_fixture()
      staff = AccountsFixtures.user_fixture()

      ProviderFixtures.assign_active_staff(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: owner.id
      })

      ProviderFixtures.assign_active_staff(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff.id
      })

      conversation_id = Ecto.UUID.generate()

      Repo.insert!(%Conversation{
        id: conversation_id,
        type: :direct,
        provider_id: provider.id,
        program_id: program.id
      })

      assert {:ok, {:ok, {added_ids, [event]}}} =
               Repo.transaction(fn ->
                 AddAssignedStaff.execute(conversation_id, program.id, owner.id)
               end)

      assert added_ids == [staff.id]
      refute KlassHero.Messaging.participant?(conversation_id, owner.id)
      assert event.payload.participant_user_ids == [staff.id]
    end

    test "no staff assigned to program — returns {:ok, {[], []}} and no events" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      owner = AccountsFixtures.user_fixture()

      conversation_id = Ecto.UUID.generate()

      Repo.insert!(%Conversation{
        id: conversation_id,
        type: :direct,
        provider_id: provider.id,
        program_id: program.id
      })

      assert {:ok, {:ok, {[], []}}} =
               Repo.transaction(fn ->
                 AddAssignedStaff.execute(conversation_id, program.id, owner.id)
               end)
    end

    test "nil program_id — returns {:ok, {[], []}} immediately" do
      owner = AccountsFixtures.user_fixture()
      conversation_id = Ecto.UUID.generate()

      assert {:ok, {[], []}} = AddAssignedStaff.execute(conversation_id, nil, owner.id)
    end

    # #784: `assign_staff_to_session/1` requires only active employment, so a
    # substitute covering one session can hold no `ProgramStaffAssignment` at all.
    # Seeding from the program roster alone cut them off from parent messaging for
    # a session they were running.
    test "seeds a staff member who only overrides one of the program's sessions" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      session = insert(:program_session_schema, program_id: program.id)
      owner = AccountsFixtures.user_fixture()
      substitute = AccountsFixtures.user_fixture()

      staff_member =
        insert(:staff_member_schema,
          provider_id: provider.id,
          user_id: substitute.id,
          invitation_status: :accepted
        )

      insert(:session_staff_assignment_schema,
        provider_id: provider.id,
        session_id: session.id,
        staff_member_id: staff_member.id
      )

      conversation_id = Ecto.UUID.generate()

      Repo.insert!(%Conversation{
        id: conversation_id,
        type: :direct,
        provider_id: provider.id,
        program_id: program.id
      })

      assert {:ok, {:ok, {added_ids, [event]}}} =
               Repo.transaction(fn ->
                 AddAssignedStaff.execute(conversation_id, program.id, owner.id)
               end)

      assert added_ids == [substitute.id]
      assert KlassHero.Messaging.participant?(conversation_id, substitute.id)
      assert event.payload.participant_user_ids == [substitute.id]
    end

    test "owner is the only staff member — returns {:ok, {[], []}}" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      owner = AccountsFixtures.user_fixture()

      ProviderFixtures.assign_active_staff(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: owner.id
      })

      conversation_id = Ecto.UUID.generate()

      Repo.insert!(%Conversation{
        id: conversation_id,
        type: :direct,
        provider_id: provider.id,
        program_id: program.id
      })

      assert {:ok, {:ok, {[], []}}} =
               Repo.transaction(fn ->
                 AddAssignedStaff.execute(conversation_id, program.id, owner.id)
               end)
    end
  end
end
