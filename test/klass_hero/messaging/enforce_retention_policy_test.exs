defmodule KlassHero.Messaging.EnforceRetentionPolicyTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.EventTestHelper
  alias KlassHero.Messaging.EnforceRetentionPolicy
  alias KlassHero.MessagingFixtures

  setup do
    EventTestHelper.setup_test_events()
    :ok
  end

  describe "execute/0" do
    test "deletes messages and conversations past retention_until" do
      provider = insert(:provider_profile_schema)
      user = AccountsFixtures.user_fixture()

      # Expired conversation (retention_until in the past)
      expired_conversation =
        insert(:conversation_schema,
          provider_id: provider.id,
          archived_at: DateTime.utc_now() |> DateTime.add(-35, :day),
          retention_until: DateTime.utc_now() |> DateTime.add(-5, :day)
        )

      insert(:participant_schema,
        conversation_id: expired_conversation.id,
        user_id: user.id
      )

      # Create a message in the expired conversation
      {:ok, _message} =
        KlassHero.Messaging.create_message(%{
          conversation_id: expired_conversation.id,
          sender_id: user.id,
          content: "This message should be deleted"
        })

      assert {:ok, result} = EnforceRetentionPolicy.execute()

      assert result.messages_deleted >= 1
      assert result.conversations_deleted >= 1

      # Verify conversation is deleted
      assert {:error, :not_found} = KlassHero.Messaging.get_conversation_by_id(expired_conversation.id)
    end

    test "does nothing when no expired data" do
      provider = insert(:provider_profile_schema)
      user = AccountsFixtures.user_fixture()

      # Active conversation (not archived)
      active_conversation = insert(:conversation_schema, provider_id: provider.id)

      insert(:participant_schema,
        conversation_id: active_conversation.id,
        user_id: user.id
      )

      {:ok, _message} =
        KlassHero.Messaging.create_message(%{
          conversation_id: active_conversation.id,
          sender_id: user.id,
          content: "This message should remain"
        })

      assert {:ok, result} = EnforceRetentionPolicy.execute()

      assert result.messages_deleted == 0
      assert result.conversations_deleted == 0

      # Verify conversation still exists
      assert {:ok, _} = KlassHero.Messaging.get_conversation_by_id(active_conversation.id)
    end

    test "publishes retention_enforced event" do
      provider = insert(:provider_profile_schema)
      user = AccountsFixtures.user_fixture()

      # Expired conversation
      expired_conversation =
        insert(:conversation_schema,
          provider_id: provider.id,
          archived_at: DateTime.utc_now() |> DateTime.add(-35, :day),
          retention_until: DateTime.utc_now() |> DateTime.add(-5, :day)
        )

      insert(:participant_schema,
        conversation_id: expired_conversation.id,
        user_id: user.id
      )

      {:ok, _message} =
        KlassHero.Messaging.create_message(%{
          conversation_id: expired_conversation.id,
          sender_id: user.id,
          content: "Message to delete"
        })

      assert {:ok, _result} = EnforceRetentionPolicy.execute()

      EventTestHelper.assert_event_published(:retention_enforced)
    end

    test "leaves active (non-archived) conversations untouched" do
      provider = insert(:provider_profile_schema)
      user = AccountsFixtures.user_fixture()

      # Active conversation (nil archived_at even though it has a theoretical retention_until)
      active_conversation =
        insert(:conversation_schema,
          provider_id: provider.id,
          archived_at: nil,
          retention_until: nil
        )

      insert(:participant_schema,
        conversation_id: active_conversation.id,
        user_id: user.id
      )

      {:ok, original_message} =
        KlassHero.Messaging.create_message(%{
          conversation_id: active_conversation.id,
          sender_id: user.id,
          content: "This message should remain"
        })

      assert {:ok, result} = EnforceRetentionPolicy.execute()

      assert result.messages_deleted == 0
      assert result.conversations_deleted == 0

      # Verify message still exists
      assert {:ok, _} = KlassHero.Messaging.get_message_by_id(original_message.id)
    end

    test "handles conversation with retention_until in the future" do
      provider = insert(:provider_profile_schema)
      user = AccountsFixtures.user_fixture()

      # Archived but retention not yet expired
      archived_conversation =
        insert(:conversation_schema,
          provider_id: provider.id,
          archived_at: DateTime.utc_now() |> DateTime.add(-10, :day),
          retention_until: DateTime.utc_now() |> DateTime.add(20, :day)
        )

      insert(:participant_schema,
        conversation_id: archived_conversation.id,
        user_id: user.id
      )

      {:ok, _message} =
        KlassHero.Messaging.create_message(%{
          conversation_id: archived_conversation.id,
          sender_id: user.id,
          content: "This message should remain until retention expires"
        })

      assert {:ok, result} = EnforceRetentionPolicy.execute()

      assert result.messages_deleted == 0
      assert result.conversations_deleted == 0

      # Verify conversation still exists
      assert {:ok, _} = KlassHero.Messaging.get_conversation_by_id(archived_conversation.id)
    end

    test "deletes multiple expired conversations and their messages" do
      provider = insert(:provider_profile_schema)
      user = AccountsFixtures.user_fixture()

      # Create multiple expired conversations
      expired1 =
        insert(:conversation_schema,
          provider_id: provider.id,
          archived_at: DateTime.utc_now() |> DateTime.add(-40, :day),
          retention_until: DateTime.utc_now() |> DateTime.add(-10, :day)
        )

      expired2 =
        insert(:conversation_schema,
          provider_id: provider.id,
          archived_at: DateTime.utc_now() |> DateTime.add(-50, :day),
          retention_until: DateTime.utc_now() |> DateTime.add(-20, :day)
        )

      for conv <- [expired1, expired2] do
        insert(:participant_schema,
          conversation_id: conv.id,
          user_id: user.id
        )

        KlassHero.Messaging.create_message(%{
          conversation_id: conv.id,
          sender_id: user.id,
          content: "Message in expired conversation"
        })
      end

      assert {:ok, result} = EnforceRetentionPolicy.execute()

      assert result.messages_deleted >= 2
      assert result.conversations_deleted >= 2

      # Verify both conversations are deleted
      assert {:error, :not_found} = KlassHero.Messaging.get_conversation_by_id(expired1.id)
      assert {:error, :not_found} = KlassHero.Messaging.get_conversation_by_id(expired2.id)
    end

    test "collects and attempts S3 deletion for attachments in expired conversations" do
      provider = insert(:provider_profile_schema)
      user = AccountsFixtures.user_fixture()

      expired_conversation =
        insert(:conversation_schema,
          provider_id: provider.id,
          archived_at: DateTime.utc_now() |> DateTime.add(-35, :day),
          retention_until: DateTime.utc_now() |> DateTime.add(-5, :day)
        )

      insert(:participant_schema,
        conversation_id: expired_conversation.id,
        user_id: user.id
      )

      {:ok, message} =
        KlassHero.Messaging.create_message(%{
          conversation_id: expired_conversation.id,
          sender_id: user.id,
          content: "Message with attachment"
        })

      # Create an attachment with a known S3 URL
      file_url = "https://bucket.fly.storage.tigris.dev/messaging/attachments/#{message.id}/photo.jpg"
      MessagingFixtures.attachment_fixture(message.id, %{file_url: file_url})

      # Retention enforcement must succeed even with attachments present.
      # The stub storage adapter gracefully handles delete calls without a running agent.
      assert {:ok, result} = EnforceRetentionPolicy.execute()
      assert result.messages_deleted >= 1
      assert result.conversations_deleted >= 1
    end

    test "succeeds when expired conversations have no attachments" do
      provider = insert(:provider_profile_schema)
      user = AccountsFixtures.user_fixture()

      expired_conversation =
        insert(:conversation_schema,
          provider_id: provider.id,
          archived_at: DateTime.utc_now() |> DateTime.add(-35, :day),
          retention_until: DateTime.utc_now() |> DateTime.add(-5, :day)
        )

      insert(:participant_schema,
        conversation_id: expired_conversation.id,
        user_id: user.id
      )

      {:ok, _message} =
        KlassHero.Messaging.create_message(%{
          conversation_id: expired_conversation.id,
          sender_id: user.id,
          content: "Message without attachment"
        })

      # No attachments created — S3 cleanup should be a no-op
      assert {:ok, result} = EnforceRetentionPolicy.execute()
      assert result.messages_deleted >= 1
      assert result.conversations_deleted >= 1
    end
  end
end
