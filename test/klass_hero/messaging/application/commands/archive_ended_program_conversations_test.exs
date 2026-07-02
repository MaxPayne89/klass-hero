defmodule KlassHero.Messaging.Application.Commands.ArchiveEndedProgramConversationsTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.EventTestHelper
  alias KlassHero.Messaging.Application.Commands.ArchiveEndedProgramConversations

  setup do
    EventTestHelper.setup_test_events()
    :ok
  end

  describe "execute/1" do
    test "archives conversations when program end_date is before cutoff" do
      provider = insert(:provider_profile_schema)

      # Program that ended 40 days ago (past the default 30 day cutoff)
      past_end_date = DateTime.utc_now() |> DateTime.add(-40, :day)
      program = insert(:program_schema, end_date: past_end_date)

      conversation =
        insert(:conversation_schema,
          type: "program_broadcast",
          provider_id: provider.id,
          program_id: program.id
        )

      assert {:ok, result} = ArchiveEndedProgramConversations.execute()

      assert result.count == 1
      assert conversation.id in result.conversation_ids

      # Verify conversation is now archived
      {:ok, archived} = KlassHero.Messaging.get_conversation_by_id(conversation.id)
      assert archived.archived_at != nil
      assert archived.retention_until != nil
    end

    test "does nothing when no programs have ended (future end_date)" do
      provider = insert(:provider_profile_schema)

      # Program that ends in the future
      future_end_date = DateTime.utc_now() |> DateTime.add(30, :day)
      program = insert(:program_schema, end_date: future_end_date)

      insert(:conversation_schema,
        type: "program_broadcast",
        provider_id: provider.id,
        program_id: program.id
      )

      assert {:ok, result} = ArchiveEndedProgramConversations.execute()
      assert result.count == 0
      assert result.conversation_ids == []
    end

    test "does nothing when conversations already archived" do
      provider = insert(:provider_profile_schema)

      # Program that ended 40 days ago
      past_end_date = DateTime.utc_now() |> DateTime.add(-40, :day)
      program = insert(:program_schema, end_date: past_end_date)

      # Already archived conversation
      insert(:conversation_schema,
        type: "program_broadcast",
        provider_id: provider.id,
        program_id: program.id,
        archived_at: DateTime.utc_now() |> DateTime.add(-5, :day),
        retention_until: DateTime.utc_now() |> DateTime.add(25, :day)
      )

      assert {:ok, result} = ArchiveEndedProgramConversations.execute()
      assert result.count == 0
      assert result.conversation_ids == []
    end

    test "publishes conversations_archived event on success" do
      provider = insert(:provider_profile_schema)

      past_end_date = DateTime.utc_now() |> DateTime.add(-40, :day)
      program = insert(:program_schema, end_date: past_end_date)

      insert(:conversation_schema,
        type: "program_broadcast",
        provider_id: provider.id,
        program_id: program.id
      )

      assert {:ok, _result} = ArchiveEndedProgramConversations.execute()

      EventTestHelper.assert_event_published(:conversations_archived, %{reason: :program_ended})
    end

    test "does not publish event when no conversations archived" do
      assert {:ok, result} = ArchiveEndedProgramConversations.execute()
      assert result.count == 0

      EventTestHelper.assert_no_events_published()
    end

    test "respects config override via days_after_program_end opt" do
      provider = insert(:provider_profile_schema)

      # Program that ended 10 days ago
      past_end_date = DateTime.utc_now() |> DateTime.add(-10, :day)
      program = insert(:program_schema, end_date: past_end_date)

      conversation =
        insert(:conversation_schema,
          type: "program_broadcast",
          provider_id: provider.id,
          program_id: program.id
        )

      # With default 30 days, this should NOT be archived
      assert {:ok, result1} = ArchiveEndedProgramConversations.execute()
      assert result1.count == 0

      # With 5 day override, this SHOULD be archived
      assert {:ok, result2} = ArchiveEndedProgramConversations.execute(days_after_program_end: 5)
      assert result2.count == 1
      assert conversation.id in result2.conversation_ids
    end

    test "ignores direct conversations (only archives program_broadcast)" do
      provider = insert(:provider_profile_schema)
      user = AccountsFixtures.user_fixture()

      # Program that ended 40 days ago
      past_end_date = DateTime.utc_now() |> DateTime.add(-40, :day)
      _program = insert(:program_schema, end_date: past_end_date)

      # Direct conversation (not program_broadcast)
      direct_conversation = insert(:conversation_schema, type: "direct", provider_id: provider.id)

      insert(:participant_schema,
        conversation_id: direct_conversation.id,
        user_id: user.id
      )

      assert {:ok, result} = ArchiveEndedProgramConversations.execute()
      assert result.count == 0
      refute direct_conversation.id in result.conversation_ids
    end

    test "ignores programs without end_date (nil)" do
      provider = insert(:provider_profile_schema)

      # Program with nil end_date (ongoing program)
      program = insert(:program_schema, end_date: nil)

      insert(:conversation_schema,
        type: "program_broadcast",
        provider_id: provider.id,
        program_id: program.id
      )

      assert {:ok, result} = ArchiveEndedProgramConversations.execute()
      assert result.count == 0
      assert result.conversation_ids == []
    end

    test "archives multiple conversations for ended programs" do
      provider = insert(:provider_profile_schema)

      # Multiple programs that ended at different past times
      program1 = insert(:program_schema, end_date: DateTime.utc_now() |> DateTime.add(-40, :day))
      program2 = insert(:program_schema, end_date: DateTime.utc_now() |> DateTime.add(-35, :day))

      conv1 =
        insert(:conversation_schema,
          type: "program_broadcast",
          provider_id: provider.id,
          program_id: program1.id
        )

      conv2 =
        insert(:conversation_schema,
          type: "program_broadcast",
          provider_id: provider.id,
          program_id: program2.id
        )

      assert {:ok, result} = ArchiveEndedProgramConversations.execute()
      assert result.count == 2
      assert conv1.id in result.conversation_ids
      assert conv2.id in result.conversation_ids
    end
  end
end
