defmodule KlassHero.Messaging.EnrollmentParticipationHandlerTest do
  use KlassHero.DataCase, async: false

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Enrollment.Domain.Events.EnrollmentEvents
  alias KlassHero.Messaging
  alias KlassHero.Messaging.EnrollmentParticipationHandler

  setup do
    setup_test_integration_events()
    :ok
  end

  describe "handle_event/1 - enrollment_created" do
    test "adds the late enrollee to the program's active broadcast conversation" do
      %{program: program, conversation: conversation} = program_with_broadcast()
      parent_user = KlassHero.AccountsFixtures.user_fixture()

      assert :ok = handle(program.id, parent_user.id)

      assert Messaging.participant?(conversation.id, parent_user.id)
    end

    # The privacy trap: `:direct` conversations also carry a program_id (set by
    # StartProgramConversation), so a program-wide backfill would drop the new
    # parent into other families' private threads.
    test "does not add the enrollee to a direct conversation for the same program" do
      %{provider: provider, program: program} = program_with_broadcast()
      other_family = KlassHero.AccountsFixtures.user_fixture()
      parent_user = KlassHero.AccountsFixtures.user_fixture()

      direct =
        insert(:conversation_schema,
          provider_id: provider.id,
          type: :direct,
          program_id: program.id
        )

      insert(:participant_schema, conversation_id: direct.id, user_id: other_family.id)

      assert :ok = handle(program.id, parent_user.id)

      refute Messaging.participant?(direct.id, parent_user.id)
    end

    test "emits :participant_added with source :later_enrollment" do
      %{program: program, conversation: conversation} = program_with_broadcast()
      parent_user = KlassHero.AccountsFixtures.user_fixture()

      assert :ok = handle(program.id, parent_user.id)

      assert_integration_event_published(:participant_added, %{
        conversation_id: conversation.id,
        participant_user_ids: [parent_user.id],
        source: :later_enrollment
      })
    end

    test "is inert when the program has no broadcast conversation" do
      program = insert(:program_schema)
      parent_user = KlassHero.AccountsFixtures.user_fixture()

      assert :ok = handle(program.id, parent_user.id)

      refute_participant_added()
    end

    test "is inert when the enrollee is already an active participant" do
      %{program: program, conversation: conversation} = program_with_broadcast()
      parent_user = KlassHero.AccountsFixtures.user_fixture()
      insert(:participant_schema, conversation_id: conversation.id, user_id: parent_user.id)

      assert :ok = handle(program.id, parent_user.id)

      refute_participant_added()
    end

    # `parent_user_id` is resolved late for invite-created enrollments
    # (Enrollment.do_create_enrollment/2), so a parent profile with no user behind
    # it yields nil. conversation_participants.user_id is NOT NULL with an FK, so
    # an unguarded insert raises past RetryHelpers straight into an Oban discard.
    test "skips when parent_user_id is nil" do
      %{program: program} = program_with_broadcast()

      assert :ok = handle(program.id, nil)

      refute_participant_added()
    end

    test "ignores unrelated events" do
      assert :ignore = EnrollmentParticipationHandler.handle_event(%{event_type: :something_else})
    end
  end

  describe "handle_event/1 - read state at join" do
    test "stamps last_read_at so pre-join broadcasts do not count as unread" do
      %{conversation: conversation, program: program, provider_user: provider_user} =
        program_with_broadcast()

      older = insert(:message_schema, conversation_id: conversation.id, sender_id: provider_user.id)
      parent_user = KlassHero.AccountsFixtures.user_fixture()

      assert :ok = handle(program.id, parent_user.id)

      {:ok, participant} = Messaging.get_participant(conversation.id, parent_user.id)

      assert participant.last_read_at == older.inserted_at
      assert Messaging.count_unread_messages(conversation.id, participant.last_read_at) == 0
    end

    # BroadcastToProgram creates the conversation, adds participants and sends the
    # message in three separately-committing steps, so an enrollment landing in
    # that window finds a broadcast with no messages yet.
    test "leaves last_read_at nil when the broadcast has no messages yet" do
      %{program: program, conversation: conversation} = program_with_broadcast()
      parent_user = KlassHero.AccountsFixtures.user_fixture()

      assert :ok = handle(program.id, parent_user.id)

      {:ok, participant} = Messaging.get_participant(conversation.id, parent_user.id)
      assert is_nil(participant.last_read_at)
    end
  end

  defp refute_participant_added do
    refute Enum.any?(get_published_integration_events(), &(&1.event_type == :participant_added)),
           "Expected no :participant_added event to be staged."
  end

  defp handle(program_id, parent_user_id) do
    Ecto.UUID.generate()
    |> EnrollmentEvents.enrollment_created(%{
      enrollment_id: Ecto.UUID.generate(),
      child_id: Ecto.UUID.generate(),
      parent_id: Ecto.UUID.generate(),
      parent_user_id: parent_user_id,
      program_id: program_id,
      status: :confirmed
    })
    |> through_outbox()
    |> EnrollmentParticipationHandler.handle_event()
  end

  defp program_with_broadcast do
    provider = insert(:provider_profile_schema)
    provider_user = KlassHero.AccountsFixtures.user_fixture()
    program = insert(:program_schema, provider_id: provider.id)

    conversation =
      insert(:conversation_schema,
        provider_id: provider.id,
        type: :program_broadcast,
        program_id: program.id
      )

    insert(:participant_schema, conversation_id: conversation.id, user_id: provider_user.id)

    %{
      provider: provider,
      provider_user: provider_user,
      program: program,
      conversation: conversation
    }
  end
end
