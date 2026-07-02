defmodule KlassHero.Messaging.Adapters.Driving.Workers.RetentionPolicyWorkerTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.EventTestHelper
  alias KlassHero.Messaging.Adapters.Driving.Workers.RetentionPolicyWorker

  setup do
    EventTestHelper.setup_test_events()
    :ok
  end

  describe "perform/1" do
    test "returns :ok on success" do
      job = %Oban.Job{}

      assert :ok = RetentionPolicyWorker.perform(job)
    end

    test "returns :ok when no expired data" do
      provider = insert(:provider_profile_schema)
      user = AccountsFixtures.user_fixture()

      # Active conversation
      active_conversation = insert(:conversation_schema, provider_id: provider.id)

      insert(:participant_schema,
        conversation_id: active_conversation.id,
        user_id: user.id
      )

      {:ok, _message} =
        KlassHero.Messaging.create_message(%{
          conversation_id: active_conversation.id,
          sender_id: user.id,
          content: "Active message"
        })

      job = %Oban.Job{}

      assert :ok = RetentionPolicyWorker.perform(job)

      # Verify conversation still exists
      assert {:ok, _} = KlassHero.Messaging.get_conversation_by_id(active_conversation.id)
    end

    test "deletes expired conversations and messages" do
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

      job = %Oban.Job{}

      assert :ok = RetentionPolicyWorker.perform(job)

      # Verify conversation is deleted
      assert {:error, :not_found} = KlassHero.Messaging.get_conversation_by_id(expired_conversation.id)

      # Verify event was published
      EventTestHelper.assert_event_published(:retention_enforced)
    end

    test "publishes retention_enforced event after cleanup" do
      provider = insert(:provider_profile_schema)
      user = AccountsFixtures.user_fixture()

      # Create expired conversation
      expired_conversation =
        insert(:conversation_schema,
          provider_id: provider.id,
          archived_at: DateTime.utc_now() |> DateTime.add(-40, :day),
          retention_until: DateTime.utc_now() |> DateTime.add(-10, :day)
        )

      insert(:participant_schema,
        conversation_id: expired_conversation.id,
        user_id: user.id
      )

      {:ok, _} =
        KlassHero.Messaging.create_message(%{
          conversation_id: expired_conversation.id,
          sender_id: user.id,
          content: "Will be deleted"
        })

      job = %Oban.Job{}

      assert :ok = RetentionPolicyWorker.perform(job)

      event = EventTestHelper.assert_event_published(:retention_enforced)
      assert event.payload.messages_deleted >= 1
      assert event.payload.conversations_deleted >= 1
    end
  end
end
