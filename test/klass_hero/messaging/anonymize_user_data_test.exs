defmodule KlassHero.Messaging.AnonymizeUserDataTest do
  @moduledoc """
  Tests for the AnonymizeUserData use case.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.AnonymizeUserData
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.Participant
  alias KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher

  describe "execute/1" do
    setup do
      setup_test_integration_events()
      :ok
    end

    test "anonymizes messages and marks participants as left, returns counts" do
      user = AccountsFixtures.user_fixture()
      conversation1 = insert(:conversation_schema)
      conversation2 = insert(:conversation_schema)

      # Two conversations with active participations
      insert(:participant_schema,
        conversation_id: conversation1.id,
        user_id: user.id,
        left_at: nil
      )

      insert(:participant_schema,
        conversation_id: conversation2.id,
        user_id: user.id,
        left_at: nil
      )

      # Three messages across two conversations
      insert(:message_schema,
        conversation_id: conversation1.id,
        sender_id: user.id,
        content: "Message 1"
      )

      insert(:message_schema,
        conversation_id: conversation1.id,
        sender_id: user.id,
        content: "Message 2"
      )

      insert(:message_schema,
        conversation_id: conversation2.id,
        sender_id: user.id,
        content: "Message 3"
      )

      assert {:ok, result} = AnonymizeUserData.execute(user.id)
      assert result.messages_anonymized == 3
      assert result.participants_updated == 2

      # Verify all message content anonymized
      messages = Repo.all(from(m in Message, where: m.sender_id == ^user.id))
      assert Enum.all?(messages, &(&1.content == "[deleted]"))

      # Verify all participants marked as left
      participants =
        Repo.all(from(p in Participant, where: p.user_id == ^user.id))

      assert Enum.all?(participants, &(not is_nil(&1.left_at)))
    end

    test "publishes message_data_anonymized integration event" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, _result} = AnonymizeUserData.execute(user.id)

      integration_event = assert_integration_event_published(:message_data_anonymized)
      assert integration_event.entity_id == user.id
      assert integration_event.source_context == :messaging
    end

    test "returns zero counts for user with no messaging data" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, result} = AnonymizeUserData.execute(user.id)
      assert result.messages_anonymized == 0
      assert result.participants_updated == 0
    end

    test "is idempotent: second call re-anonymizes messages but finds no active participations" do
      user = AccountsFixtures.user_fixture()
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id,
        left_at: nil
      )

      insert(:message_schema,
        conversation_id: conversation.id,
        sender_id: user.id,
        content: "Original message"
      )

      # First call: anonymizes message and marks participant as left
      assert {:ok, first_result} = AnonymizeUserData.execute(user.id)
      assert first_result.messages_anonymized == 1
      assert first_result.participants_updated == 1

      # Second call: re-sets content to [deleted] (count still 1), but no active participations left
      assert {:ok, second_result} = AnonymizeUserData.execute(user.id)
      assert second_result.messages_anonymized == 1
      assert second_result.participants_updated == 0
    end

    test "succeeds even when integration event publish fails" do
      user = AccountsFixtures.user_fixture()
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id,
        left_at: nil
      )

      insert(:message_schema,
        conversation_id: conversation.id,
        sender_id: user.id,
        content: "Original message"
      )

      # Clear integration events from fixture setup (user registration triggers one)
      clear_integration_events()
      TestIntegrationEventPublisher.configure_publish_error(:pubsub_down)

      # Use case returns {:ok, _} — publish failure is swallowed with a warning log
      assert {:ok, result} = AnonymizeUserData.execute(user.id)
      assert result.messages_anonymized == 1
      assert result.participants_updated == 1

      # DB changes persisted despite publish failure
      message = Repo.one!(from(m in Message, where: m.sender_id == ^user.id))
      assert message.content == "[deleted]"

      participant =
        Repo.one!(from(p in Participant, where: p.user_id == ^user.id))

      refute is_nil(participant.left_at)

      assert_no_integration_events_published()
    end
  end
end
