defmodule KlassHero.Messaging.Adapters.Driving.Events.MessagingEventHandlerTest do
  @moduledoc """
  Tests for MessagingEventHandler handling of user_anonymized events.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Accounts.Domain.Events.AccountsIntegrationEvents
  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.Adapters.Driving.Events.MessagingEventHandler
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.Participant

  describe "handle_event/1 for :user_anonymized" do
    setup do
      setup_test_integration_events()
      :ok
    end

    test "anonymizes message content and marks participant as left" do
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
        content: "Secret message"
      )

      event =
        AccountsIntegrationEvents.user_anonymized(
          user.id,
          %{anonymized_email: "deleted_#{user.id}@anonymized.local"}
        )

      assert :ok == MessagingEventHandler.handle_event(event)

      # Verify message content was anonymized
      reloaded_message =
        Repo.one!(
          from(m in Message,
            where: m.sender_id == ^user.id
          )
        )

      assert reloaded_message.content == "[deleted]"

      # Verify participant was marked as left
      reloaded_participant =
        Repo.one!(
          from(p in Participant,
            where: p.user_id == ^user.id and p.conversation_id == ^conversation.id
          )
        )

      refute is_nil(reloaded_participant.left_at)
    end

    test "publishes message_data_anonymized integration event" do
      user = AccountsFixtures.user_fixture()

      event =
        AccountsIntegrationEvents.user_anonymized(
          user.id,
          %{anonymized_email: "deleted_#{user.id}@anonymized.local"}
        )

      assert :ok == MessagingEventHandler.handle_event(event)

      integration_event = assert_integration_event_published(:message_data_anonymized)
      assert integration_event.entity_id == user.id
    end

    test "returns :ok for user with no messaging data" do
      user = AccountsFixtures.user_fixture()

      event =
        AccountsIntegrationEvents.user_anonymized(
          user.id,
          %{anonymized_email: "deleted_#{user.id}@anonymized.local"}
        )

      assert :ok == MessagingEventHandler.handle_event(event)
    end
  end

  describe "handle_event/1 for unknown events" do
    test "ignores unknown event types" do
      event = %{event_type: :unknown_event, entity_id: Ecto.UUID.generate(), payload: %{}}

      assert :ignore == MessagingEventHandler.handle_event(event)
    end
  end

  describe "subscribed_events/0" do
    test "includes :user_anonymized" do
      assert :user_anonymized in MessagingEventHandler.subscribed_events()
    end
  end
end
