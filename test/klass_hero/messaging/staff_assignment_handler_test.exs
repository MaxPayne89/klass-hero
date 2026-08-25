defmodule KlassHero.Messaging.StaffAssignmentHandlerTest do
  use KlassHero.DataCase, async: false

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Messaging.StaffAssignmentHandler
  alias KlassHero.Provider
  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Provider.SessionStaffAssignment
  alias KlassHero.Provider.StaffMember

  setup do
    setup_test_integration_events()
    :ok
  end

  describe "handle_event/1 - staff_assigned_to_program" do
    test "skips when staff_user_id is nil" do
      event = build_assignment_event(Ecto.UUID.generate(), Ecto.UUID.generate(), nil)
      assert :ok = StaffAssignmentHandler.handle_event(event)
    end

    test "adds staff to existing active conversations for the program" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      parent_user = KlassHero.AccountsFixtures.user_fixture()
      staff_user = KlassHero.AccountsFixtures.user_fixture()
      staff_user_id = staff_user.id

      # Create existing conversation for this program
      conversation =
        insert(:conversation_schema,
          provider_id: provider.id,
          type: "direct",
          program_id: program.id
        )

      insert(:participant_schema, conversation_id: conversation.id, user_id: parent_user.id)

      event = build_assignment_event(provider.id, program.id, staff_user_id)
      assert :ok = StaffAssignmentHandler.handle_event(event)

      # Staff should now be a participant
      assert KlassHero.Messaging.participant?(conversation.id, staff_user_id)
    end

    test "emits :participant_added per back-filled conversation with source :later_assignment" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      parent_user = KlassHero.AccountsFixtures.user_fixture()
      staff_user = KlassHero.AccountsFixtures.user_fixture()

      conv_a =
        insert(:conversation_schema,
          provider_id: provider.id,
          type: "direct",
          program_id: program.id
        )

      conv_b =
        insert(:conversation_schema,
          provider_id: provider.id,
          type: "direct",
          program_id: program.id
        )

      insert(:participant_schema, conversation_id: conv_a.id, user_id: parent_user.id)
      insert(:participant_schema, conversation_id: conv_b.id, user_id: parent_user.id)

      event = build_assignment_event(provider.id, program.id, staff_user.id)
      assert :ok = StaffAssignmentHandler.handle_event(event)

      events =
        Enum.filter(
          get_published_integration_events(),
          &(&1.event_type == :participant_added)
        )

      assert length(events) == 2
      conv_ids = events |> Enum.map(& &1.entity_id) |> Enum.sort()
      assert conv_ids == Enum.sort([conv_a.id, conv_b.id])

      assert Enum.all?(events, fn e ->
               e.payload.participant_user_ids == [staff_user.id] and
                 e.payload.source == :later_assignment
             end)
    end

    # Same rule as the parent back-fill (#381): arriving mid-programme should not
    # arrive as a wall of notifications. History stays readable; the badge starts
    # at the moment of assignment.
    test "stamps the read cursor at assignment so prior messages are not unread" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      parent_user = KlassHero.AccountsFixtures.user_fixture()
      staff_user = KlassHero.AccountsFixtures.user_fixture()

      conversation =
        insert(:conversation_schema,
          provider_id: provider.id,
          type: "direct",
          program_id: program.id
        )

      insert(:participant_schema, conversation_id: conversation.id, user_id: parent_user.id)
      older = insert(:message_schema, conversation_id: conversation.id, sender_id: parent_user.id)

      event = build_assignment_event(provider.id, program.id, staff_user.id)
      assert :ok = StaffAssignmentHandler.handle_event(event)

      {:ok, participant} = KlassHero.Messaging.get_participant(conversation.id, staff_user.id)

      # The cursor is the contract; that it zeroes the badge is covered end-to-end
      # in test/flows/messaging_broadcast_test.exs, against the counter the UI reads.
      assert participant.last_read_at == older.inserted_at
    end

    test "emits no :participant_added when staff is already in every program conversation" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      staff_user = KlassHero.AccountsFixtures.user_fixture()

      conv =
        insert(:conversation_schema,
          provider_id: provider.id,
          type: "direct",
          program_id: program.id
        )

      insert(:participant_schema, conversation_id: conv.id, user_id: staff_user.id)

      event = build_assignment_event(provider.id, program.id, staff_user.id)
      assert :ok = StaffAssignmentHandler.handle_event(event)

      refute Enum.any?(
               get_published_integration_events(),
               &(&1.event_type == :participant_added)
             )
    end
  end

  describe "handle_event/1 - staff_unassigned_from_program" do
    # #1309: the assign clause guarded nil, the unassign clause did not, so
    # removing a staff member who had not yet claimed their invite compared a
    # column against nil and crashed a :critical handler through all 10 attempts.
    test "skips when staff_user_id is nil" do
      event = build_unassignment_event(Ecto.UUID.generate(), Ecto.UUID.generate(), nil)
      assert :ok = StaffAssignmentHandler.handle_event(event)
    end

    test "removes staff from active program conversations and emits :participant_removed per conversation" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      parent_user = KlassHero.AccountsFixtures.user_fixture()
      staff_user = KlassHero.AccountsFixtures.user_fixture()

      conv_a =
        insert(:conversation_schema,
          provider_id: provider.id,
          type: "direct",
          program_id: program.id
        )

      conv_b =
        insert(:conversation_schema,
          provider_id: provider.id,
          type: "direct",
          program_id: program.id
        )

      insert(:participant_schema, conversation_id: conv_a.id, user_id: parent_user.id)
      insert(:participant_schema, conversation_id: conv_a.id, user_id: staff_user.id)
      insert(:participant_schema, conversation_id: conv_b.id, user_id: parent_user.id)
      insert(:participant_schema, conversation_id: conv_b.id, user_id: staff_user.id)

      event = build_unassignment_event(provider.id, program.id, staff_user.id)
      assert :ok = StaffAssignmentHandler.handle_event(event)

      refute KlassHero.Messaging.participant?(conv_a.id, staff_user.id)
      refute KlassHero.Messaging.participant?(conv_b.id, staff_user.id)

      events =
        Enum.filter(
          get_published_integration_events(),
          &(&1.event_type == :participant_removed)
        )

      assert length(events) == 2

      assert Enum.all?(events, fn e ->
               e.payload.participant_user_ids == [staff_user.id] and
                 e.payload.source == :staff_unassignment
             end)
    end
  end

  # #784. The session payload is a superset of the program one, so these exercise
  # the same add/remove paths through a wider `subscribed_events/0`.
  describe "handle_event/1 - staff_assigned_to_session" do
    test "skips when staff_user_id is nil" do
      event = build_session_assignment_event(Ecto.UUID.generate(), Ecto.UUID.generate(), nil)
      assert :ok = StaffAssignmentHandler.handle_event(event)
    end

    test "back-fills a session-only substitute into the program's active conversations" do
      %{provider: provider, program: program} = program_with_conversation()
      conversation = program.conversation
      substitute = KlassHero.AccountsFixtures.user_fixture()

      event = build_session_assignment_event(provider.id, program.id, substitute.id)
      assert :ok = StaffAssignmentHandler.handle_event(event)

      assert KlassHero.Messaging.participant?(conversation.id, substitute.id)

      assert [participant_added] =
               Enum.filter(get_published_integration_events(), &(&1.event_type == :participant_added))

      assert participant_added.entity_id == conversation.id
      assert participant_added.payload.participant_user_ids == [substitute.id]
      assert participant_added.payload.source == :later_assignment
    end
  end

  describe "handle_event/1 - the keep-guard" do
    test "staff_unassigned_from_session evicts when no claim on the program remains" do
      %{provider: provider, program: program} = program_with_conversation()
      conversation = program.conversation
      staff_user = KlassHero.AccountsFixtures.user_fixture()
      insert(:participant_schema, conversation_id: conversation.id, user_id: staff_user.id)

      event = build_session_unassignment_event(provider.id, program.id, staff_user.id)
      assert :ok = StaffAssignmentHandler.handle_event(event)

      refute KlassHero.Messaging.participant?(conversation.id, staff_user.id)
    end

    test "staff_unassigned_from_session keeps someone still on the program roster" do
      %{provider: provider, program: program} = program_with_conversation()
      conversation = program.conversation
      staff = claimed_staff_on_program(provider.id, program.id)
      insert(:participant_schema, conversation_id: conversation.id, user_id: staff.user_id)

      event = build_session_unassignment_event(provider.id, program.id, staff.user_id)
      assert :ok = StaffAssignmentHandler.handle_event(event)

      assert KlassHero.Messaging.participant?(conversation.id, staff.user_id)
    end

    # The mirror of #784: without the guard, taking someone off the *program*
    # would evict them from conversations for a session they still run.
    test "staff_unassigned_from_program keeps someone who still overrides a session" do
      %{provider: provider, program: program} = program_with_conversation()
      conversation = program.conversation
      staff = claimed_staff_overriding_session(provider.id, program.id)
      insert(:participant_schema, conversation_id: conversation.id, user_id: staff.user_id)

      event = build_unassignment_event(provider.id, program.id, staff.user_id)
      assert :ok = StaffAssignmentHandler.handle_event(event)

      assert KlassHero.Messaging.participant?(conversation.id, staff.user_id)
    end
  end

  defp program_with_conversation do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    parent_user = KlassHero.AccountsFixtures.user_fixture()

    conversation =
      insert(:conversation_schema, provider_id: provider.id, type: "direct", program_id: program.id)

    insert(:participant_schema, conversation_id: conversation.id, user_id: parent_user.id)

    %{provider: provider, program: Map.put(program, :conversation, conversation)}
  end

  defp claimed_staff(provider_id) do
    insert(:staff_member_schema,
      provider_id: provider_id,
      user_id: KlassHero.AccountsFixtures.user_fixture().id,
      invitation_status: :accepted
    )
  end

  defp claimed_staff_on_program(provider_id, program_id) do
    staff = claimed_staff(provider_id)

    {:ok, _} =
      KlassHero.Provider.assign_staff_to_program(%{
        provider_id: provider_id,
        program_id: program_id,
        staff_member_id: staff.id
      })

    staff
  end

  defp claimed_staff_overriding_session(provider_id, program_id) do
    staff = claimed_staff(provider_id)
    session = insert(:program_session_schema, program_id: program_id)

    insert(:session_staff_assignment_schema,
      provider_id: provider_id,
      session_id: session.id,
      staff_member_id: staff.id
    )

    staff
  end

  # Built through the real producer constructors, not hand-rolled maps. The
  # hand-rolled ones carried `assigned_at`/`unassigned_at`, which production
  # payloads deliberately omit (provider_events.ex) — so the tests asserted
  # against a payload shape the handler never actually receives (#1309).
  defp build_assignment_event(provider_id, program_id, staff_user_id) do
    Provider.Events.staff_assigned_to_program(
      assignment(provider_id, program_id),
      %StaffMember{user_id: staff_user_id}
    )
  end

  defp build_unassignment_event(provider_id, program_id, staff_user_id) do
    Provider.Events.staff_unassigned_from_program(
      assignment(provider_id, program_id),
      %StaffMember{user_id: staff_user_id}
    )
  end

  defp build_session_assignment_event(provider_id, program_id, staff_user_id) do
    Provider.Events.staff_assigned_to_session(
      session_assignment(provider_id),
      %StaffMember{user_id: staff_user_id},
      program_id
    )
  end

  defp build_session_unassignment_event(provider_id, program_id, staff_user_id) do
    Provider.Events.staff_unassigned_from_session(
      session_assignment(provider_id),
      %StaffMember{user_id: staff_user_id},
      program_id
    )
  end

  defp assignment(provider_id, program_id) do
    %ProgramStaffAssignment{
      provider_id: provider_id,
      program_id: program_id,
      staff_member_id: Ecto.UUID.generate()
    }
  end

  # A session override carries no program_id of its own — the producer passes it
  # separately (provider_events.ex), which is why these constructors take three
  # arguments where the program-level pair takes two.
  defp session_assignment(provider_id) do
    %SessionStaffAssignment{
      provider_id: provider_id,
      session_id: Ecto.UUID.generate(),
      staff_member_id: Ecto.UUID.generate()
    }
  end
end
