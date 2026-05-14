defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ConversationRepositoryTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ConversationRepository
  alias KlassHero.Messaging.Domain.Models.Conversation

  describe "create/1" do
    test "creates direct conversation with valid attributes" do
      provider = insert(:provider_profile_schema)

      attrs = %{
        type: :direct,
        provider_id: provider.id
      }

      assert {:ok, conversation} = ConversationRepository.create(attrs)
      assert %Conversation{} = conversation
      assert conversation.type == :direct
      assert conversation.provider_id == provider.id
      assert is_nil(conversation.program_id)
    end

    test "creates broadcast conversation with valid attributes" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)

      attrs = %{
        type: :program_broadcast,
        provider_id: provider.id,
        program_id: program.id,
        subject: "Important Update"
      }

      assert {:ok, conversation} = ConversationRepository.create(attrs)
      assert conversation.type == :program_broadcast
      assert conversation.program_id == program.id
      assert conversation.subject == "Important Update"
    end

    test "returns duplicate_broadcast error for existing active broadcast" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)

      attrs = %{
        type: :program_broadcast,
        provider_id: provider.id,
        program_id: program.id
      }

      assert {:ok, _first} = ConversationRepository.create(attrs)
      assert {:error, :duplicate_broadcast} = ConversationRepository.create(attrs)
    end

    test "returns error when required fields are missing" do
      attrs = %{type: :direct}

      assert {:error, changeset} = ConversationRepository.create(attrs)
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "get_by_id/2" do
    test "returns conversation when found" do
      conversation_schema = insert(:conversation_schema)

      assert {:ok, conversation} = ConversationRepository.get_by_id(conversation_schema.id)
      assert %Conversation{} = conversation
      assert conversation.id == conversation_schema.id
    end

    test "returns not_found when conversation does not exist" do
      assert {:error, :not_found} = ConversationRepository.get_by_id(Ecto.UUID.generate())
    end

    test "preloads participants when requested" do
      conversation_schema = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation_schema.id,
        user_id: user.id
      )

      assert {:ok, conversation} =
               ConversationRepository.get_by_id(conversation_schema.id, preload: [:participants])

      assert length(conversation.participants) == 1
      assert hd(conversation.participants).user_id == user.id
    end
  end

  describe "find_direct_conversation/2" do
    test "returns existing direct conversation between provider and user" do
      provider = insert(:provider_profile_schema)
      user = AccountsFixtures.user_fixture()

      conversation_schema = insert(:conversation_schema, provider_id: provider.id)

      insert(:participant_schema,
        conversation_id: conversation_schema.id,
        user_id: user.id
      )

      assert {:ok, conversation} =
               ConversationRepository.find_direct_conversation(provider.id, user.id)

      assert conversation.id == conversation_schema.id
    end

    test "returns not_found when no direct conversation exists" do
      provider = insert(:provider_profile_schema)
      user = AccountsFixtures.user_fixture()

      assert {:error, :not_found} =
               ConversationRepository.find_direct_conversation(provider.id, user.id)
    end

    test "ignores archived conversations" do
      provider = insert(:provider_profile_schema)
      user = AccountsFixtures.user_fixture()

      conversation_schema =
        insert(:conversation_schema,
          provider_id: provider.id,
          archived_at: DateTime.utc_now()
        )

      insert(:participant_schema,
        conversation_id: conversation_schema.id,
        user_id: user.id
      )

      assert {:error, :not_found} =
               ConversationRepository.find_direct_conversation(provider.id, user.id)
    end
  end

  describe "list_for_user/2" do
    test "returns conversations for user" do
      user = AccountsFixtures.user_fixture()
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      assert {:ok, conversations, has_more} = ConversationRepository.list_for_user(user.id)
      assert length(conversations) == 1
      assert hd(conversations).id == conversation.id
      refute has_more
    end

    test "excludes archived conversations" do
      user = AccountsFixtures.user_fixture()

      archived_conversation =
        insert(:conversation_schema,
          archived_at: DateTime.utc_now()
        )

      insert(:participant_schema,
        conversation_id: archived_conversation.id,
        user_id: user.id
      )

      assert {:ok, conversations, _has_more} = ConversationRepository.list_for_user(user.id)
      assert conversations == []
    end

    test "returns has_more when more conversations exist" do
      user = AccountsFixtures.user_fixture()

      for _i <- 1..3 do
        conversation = insert(:conversation_schema)

        insert(:participant_schema,
          conversation_id: conversation.id,
          user_id: user.id
        )
      end

      assert {:ok, conversations, has_more} =
               ConversationRepository.list_for_user(user.id, limit: 2)

      assert length(conversations) == 2
      assert has_more
    end

    test "returns empty list when user has no conversations" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, [], false} = ConversationRepository.list_for_user(user.id)
    end
  end

  describe "archive/1" do
    test "sets archived_at and retention_until timestamps" do
      conversation_schema = insert(:conversation_schema)
      {:ok, conversation} = ConversationRepository.get_by_id(conversation_schema.id)

      assert {:ok, archived} = ConversationRepository.archive(conversation)
      assert archived.archived_at != nil
      assert archived.retention_until != nil
    end

    test "increments lock_version" do
      conversation_schema = insert(:conversation_schema)
      {:ok, conversation} = ConversationRepository.get_by_id(conversation_schema.id)
      initial_version = conversation.lock_version

      {:ok, archived} = ConversationRepository.archive(conversation)
      assert archived.lock_version == initial_version + 1
    end

    test "returns not_found for non-existent conversation" do
      fake_conversation = %Conversation{
        id: Ecto.UUID.generate(),
        type: :direct,
        provider_id: Ecto.UUID.generate(),
        lock_version: 1
      }

      assert {:error, :not_found} = ConversationRepository.archive(fake_conversation)
    end
  end

  describe "archive_ended_program_conversations/2" do
    @retention_days 30

    test "archives conversations for programs that ended before cutoff" do
      provider = insert(:provider_profile_schema)

      # Program that ended 40 days ago
      past_end_date = DateTime.utc_now() |> DateTime.add(-40, :day) |> DateTime.truncate(:second)
      program = insert(:program_schema, end_date: past_end_date)

      conversation =
        insert(:conversation_schema,
          type: "program_broadcast",
          provider_id: provider.id,
          program_id: program.id
        )

      # Cutoff datetime is 30 days ago (start of day)
      cutoff_date =
        Date.utc_today()
        |> Date.add(-30)
        |> DateTime.new!(~T[00:00:00], "Etc/UTC")

      assert {:ok, %{count: 1, conversation_ids: ids}} =
               ConversationRepository.archive_ended_program_conversations(
                 cutoff_date,
                 @retention_days
               )

      assert conversation.id in ids

      # Verify conversation is archived
      {:ok, archived} = ConversationRepository.get_by_id(conversation.id)
      assert archived.archived_at != nil
      assert archived.retention_until != nil
    end

    test "returns empty result when no matching conversations" do
      cutoff_date =
        Date.utc_today()
        |> Date.add(-30)
        |> DateTime.new!(~T[00:00:00], "Etc/UTC")

      assert {:ok, %{count: 0, conversation_ids: []}} =
               ConversationRepository.archive_ended_program_conversations(
                 cutoff_date,
                 @retention_days
               )
    end

    test "ignores direct conversations" do
      provider = insert(:provider_profile_schema)
      user = AccountsFixtures.user_fixture()

      # Program that ended
      past_end_date = DateTime.utc_now() |> DateTime.add(-40, :day) |> DateTime.truncate(:second)
      _program = insert(:program_schema, end_date: past_end_date)

      # Direct conversation (not program_broadcast)
      direct_conversation = insert(:conversation_schema, type: "direct", provider_id: provider.id)

      insert(:participant_schema,
        conversation_id: direct_conversation.id,
        user_id: user.id
      )

      cutoff_date =
        Date.utc_today()
        |> Date.add(-30)
        |> DateTime.new!(~T[00:00:00], "Etc/UTC")

      assert {:ok, %{count: 0, conversation_ids: []}} =
               ConversationRepository.archive_ended_program_conversations(
                 cutoff_date,
                 @retention_days
               )
    end

    test "ignores already archived conversations" do
      provider = insert(:provider_profile_schema)

      past_end_date = DateTime.utc_now() |> DateTime.add(-40, :day) |> DateTime.truncate(:second)
      program = insert(:program_schema, end_date: past_end_date)

      # Already archived conversation
      insert(:conversation_schema,
        type: "program_broadcast",
        provider_id: provider.id,
        program_id: program.id,
        archived_at: DateTime.utc_now() |> DateTime.add(-5, :day),
        retention_until: DateTime.utc_now() |> DateTime.add(25, :day)
      )

      cutoff_date =
        Date.utc_today()
        |> Date.add(-30)
        |> DateTime.new!(~T[00:00:00], "Etc/UTC")

      assert {:ok, %{count: 0, conversation_ids: []}} =
               ConversationRepository.archive_ended_program_conversations(
                 cutoff_date,
                 @retention_days
               )
    end

    test "ignores programs with nil end_date" do
      provider = insert(:provider_profile_schema)

      # Program with nil end_date
      program = insert(:program_schema, end_date: nil)

      insert(:conversation_schema,
        type: "program_broadcast",
        provider_id: provider.id,
        program_id: program.id
      )

      cutoff_date =
        Date.utc_today()
        |> Date.add(-30)
        |> DateTime.new!(~T[00:00:00], "Etc/UTC")

      assert {:ok, %{count: 0, conversation_ids: []}} =
               ConversationRepository.archive_ended_program_conversations(
                 cutoff_date,
                 @retention_days
               )
    end

    test "sets retention_until based on provided retention_days" do
      provider = insert(:provider_profile_schema)

      past_end_date = DateTime.utc_now() |> DateTime.add(-40, :day) |> DateTime.truncate(:second)
      program = insert(:program_schema, end_date: past_end_date)

      conversation =
        insert(:conversation_schema,
          type: "program_broadcast",
          provider_id: provider.id,
          program_id: program.id
        )

      cutoff_date =
        Date.utc_today()
        |> Date.add(-30)
        |> DateTime.new!(~T[00:00:00], "Etc/UTC")

      custom_retention_days = 45

      assert {:ok, %{count: 1}} =
               ConversationRepository.archive_ended_program_conversations(
                 cutoff_date,
                 custom_retention_days
               )

      {:ok, archived} = ConversationRepository.get_by_id(conversation.id)

      # retention_until should be approximately 45 days from now
      expected_retention = DateTime.add(DateTime.utc_now(), custom_retention_days, :day)
      diff_seconds = DateTime.diff(archived.retention_until, expected_retention)

      # Allow 5 seconds tolerance for test execution time
      assert abs(diff_seconds) < 5
    end
  end

  describe "get_total_unread_count/1" do
    test "returns 0 for user with no conversations" do
      user = AccountsFixtures.user_fixture()

      assert ConversationRepository.get_total_unread_count(user.id) == 0
    end

    test "returns 0 for user with all messages read" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id,
        last_read_at: DateTime.utc_now()
      )

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: other_user.id
      )

      insert(:message_schema,
        conversation_id: conversation.id,
        sender_id: other_user.id,
        inserted_at: DateTime.utc_now() |> DateTime.add(-1, :hour)
      )

      assert ConversationRepository.get_total_unread_count(user.id) == 0
    end

    test "returns correct count of unread messages" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      conversation = insert(:conversation_schema)

      last_read = DateTime.utc_now() |> DateTime.add(-1, :hour)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id,
        last_read_at: last_read
      )

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: other_user.id
      )

      for _ <- 1..3 do
        insert(:message_schema,
          conversation_id: conversation.id,
          sender_id: other_user.id,
          inserted_at: DateTime.utc_now()
        )
      end

      assert ConversationRepository.get_total_unread_count(user.id) == 3
    end

    test "excludes archived conversations" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()

      archived_conversation =
        insert(:conversation_schema,
          archived_at: DateTime.utc_now()
        )

      insert(:participant_schema,
        conversation_id: archived_conversation.id,
        user_id: user.id,
        last_read_at: nil
      )

      insert(:participant_schema,
        conversation_id: archived_conversation.id,
        user_id: other_user.id
      )

      insert(:message_schema,
        conversation_id: archived_conversation.id,
        sender_id: other_user.id
      )

      assert ConversationRepository.get_total_unread_count(user.id) == 0
    end

    test "excludes messages from left conversations" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id,
        last_read_at: nil,
        left_at: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: other_user.id
      )

      insert(:message_schema,
        conversation_id: conversation.id,
        sender_id: other_user.id
      )

      assert ConversationRepository.get_total_unread_count(user.id) == 0
    end
  end

  describe "delete_expired/1" do
    test "deletes archived conversations past retention_until" do
      provider = insert(:provider_profile_schema)

      # Expired conversation
      expired_conversation =
        insert(:conversation_schema,
          provider_id: provider.id,
          archived_at: DateTime.utc_now() |> DateTime.add(-35, :day),
          retention_until: DateTime.utc_now() |> DateTime.add(-5, :day)
        )

      now = DateTime.utc_now()

      assert {:ok, count} = ConversationRepository.delete_expired(now)
      assert count >= 1

      # Verify conversation is deleted
      assert {:error, :not_found} = ConversationRepository.get_by_id(expired_conversation.id)
    end

    test "returns 0 when no expired conversations" do
      provider = insert(:provider_profile_schema)

      # Active conversation
      insert(:conversation_schema, provider_id: provider.id)

      now = DateTime.utc_now()

      assert {:ok, 0} = ConversationRepository.delete_expired(now)
    end

    test "does not delete conversations with future retention_until" do
      provider = insert(:provider_profile_schema)

      # Archived but retention not yet expired
      active_conversation =
        insert(:conversation_schema,
          provider_id: provider.id,
          archived_at: DateTime.utc_now() |> DateTime.add(-10, :day),
          retention_until: DateTime.utc_now() |> DateTime.add(20, :day)
        )

      now = DateTime.utc_now()

      assert {:ok, 0} = ConversationRepository.delete_expired(now)

      # Verify conversation still exists
      assert {:ok, _} = ConversationRepository.get_by_id(active_conversation.id)
    end
  end

  describe "list_active_program_conversation_ids_without_participant/2" do
    test "returns conversation IDs where user is not a participant" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      user = AccountsFixtures.user_fixture()

      conv1 =
        insert(:conversation_schema,
          provider_id: provider.id,
          program_id: program.id,
          type: "direct"
        )

      conv2 =
        insert(:conversation_schema,
          provider_id: provider.id,
          program_id: program.id,
          type: "direct"
        )

      # User is participant in conv1 only
      insert(:participant_schema, conversation_id: conv1.id, user_id: user.id)

      result =
        ConversationRepository.list_active_program_conversation_ids_without_participant(
          program.id,
          user.id
        )

      assert result == [conv2.id]
    end

    test "excludes archived conversations" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      user = AccountsFixtures.user_fixture()

      insert(:conversation_schema,
        provider_id: provider.id,
        program_id: program.id,
        type: "direct",
        archived_at: DateTime.utc_now()
      )

      result =
        ConversationRepository.list_active_program_conversation_ids_without_participant(
          program.id,
          user.id
        )

      assert result == []
    end

    test "returns empty list when user is participant in all conversations" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      user = AccountsFixtures.user_fixture()

      conv =
        insert(:conversation_schema,
          provider_id: provider.id,
          program_id: program.id,
          type: "direct"
        )

      insert(:participant_schema, conversation_id: conv.id, user_id: user.id)

      result =
        ConversationRepository.list_active_program_conversation_ids_without_participant(
          program.id,
          user.id
        )

      assert result == []
    end

    test "treats soft-left participations as 'not a participant' so the conversation is returned" do
      # Why this matters: the staff-unassignment flow now soft-removes (sets
      # `left_at`) instead of deleting. A subsequent re-assignment must see
      # those conversations again — otherwise the staff is permanently locked
      # out of every program conversation they've ever left.
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      user = AccountsFixtures.user_fixture()

      conv =
        insert(:conversation_schema,
          provider_id: provider.id,
          program_id: program.id,
          type: "direct"
        )

      insert(:participant_schema,
        conversation_id: conv.id,
        user_id: user.id,
        left_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      result =
        ConversationRepository.list_active_program_conversation_ids_without_participant(
          program.id,
          user.id
        )

      assert result == [conv.id],
             "left-but-recorded participations must NOT block re-assignment"
    end
  end
end
