defmodule KlassHero.Messaging.MessagingEventHandlerTest do
  @moduledoc """
  Tests for MessagingEventHandler handling of user_anonymized events.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Accounts
  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.MessagingEventHandler
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
        Accounts.Events.user_anonymized(
          %{id: user.id, email: "deleted_#{user.id}@anonymized.local"},
          %{previous_email: user.email}
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

      assert %DateTime{} = reloaded_participant.left_at
    end

    # A "publishes :message_data_anonymized" test stood here — see the note in
    # `anonymize_user_data_test.exs`. The handler's effect is asserted above.

    test "returns :ok for user with no messaging data" do
      user = AccountsFixtures.user_fixture()

      event =
        Accounts.Events.user_anonymized(
          %{id: user.id, email: "deleted_#{user.id}@anonymized.local"},
          %{previous_email: user.email}
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
