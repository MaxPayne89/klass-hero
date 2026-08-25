defmodule KlassHero.Messaging.AddUserToConversationsTest do
  @moduledoc """
  Guards the seating rule shared by every path that adds someone to a conversation:
  they arrive with their read cursor at whatever the conversation already held.

  Both callers depend on it — `StaffAssignmentHandler` for a mid-programme
  assignment, `EnrollmentParticipationHandler` for a late enrolment — so neither
  passes a cursor of its own. That is deliberate: a rule each caller has to remember
  is a rule the next caller forgets.
  """

  use KlassHero.DataCase, async: true

  import Ecto.Query
  import KlassHero.Factory

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.Participant
  alias KlassHero.Repo

  setup do
    conversation = insert(:conversation_schema)
    speaker = insert(:participant_schema, conversation_id: conversation.id)
    user = KlassHero.AccountsFixtures.user_fixture()

    %{conversation: conversation, speaker: speaker, user: user}
  end

  test "a fresh join is stamped at the newest existing message", ctx do
    insert(:message_schema, conversation_id: ctx.conversation.id, sender_id: ctx.speaker.user_id)
    newest = insert(:message_schema, conversation_id: ctx.conversation.id, sender_id: ctx.speaker.user_id)

    assert {:ok, _} = Messaging.add_user_to_conversations(ctx.user.id, [ctx.conversation.id])

    assert {:ok, %{last_read_at: cursor}} =
             Messaging.get_participant(ctx.conversation.id, ctx.user.id)

    assert cursor == newest.inserted_at
    refute anything_after?(ctx.conversation.id, cursor)
  end

  test "an empty conversation leaves the cursor nil, so what comes next is unread", ctx do
    assert {:ok, _} = Messaging.add_user_to_conversations(ctx.user.id, [ctx.conversation.id])

    assert {:ok, %{last_read_at: nil}} =
             Messaging.get_participant(ctx.conversation.id, ctx.user.id)
  end

  # A soft-deleted message is invisible but still counts towards the anchor:
  # ConversationSummaries counts unread without a deleted_at filter, so anchoring on
  # the newest *visible* message would badge a message the reader cannot open.
  test "a soft-deleted newest message still anchors the cursor", ctx do
    insert(:message_schema, conversation_id: ctx.conversation.id, sender_id: ctx.speaker.user_id)

    deleted =
      insert(:message_schema,
        conversation_id: ctx.conversation.id,
        sender_id: ctx.speaker.user_id,
        deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

    assert {:ok, _} = Messaging.add_user_to_conversations(ctx.user.id, [ctx.conversation.id])

    assert {:ok, %{last_read_at: cursor}} =
             Messaging.get_participant(ctx.conversation.id, ctx.user.id)

    assert cursor == deleted.inserted_at
    refute anything_after?(ctx.conversation.id, cursor)
  end

  # Counter-agnostic on purpose. The badge users see comes from
  # `ConversationSummaries.unread_count`, which counts deleted messages;
  # `Messaging.count_unread_messages/2` does not. Asserting through either would
  # prove the invariant only for the counter that happens to agree with it —
  # "nothing in this conversation postdates the cursor" is what makes both read
  # zero. The live badge itself is covered end-to-end in
  # `test/flows/messaging_broadcast_test.exs`.
  defp anything_after?(conversation_id, cursor) do
    Repo.exists?(
      from m in Message,
        where: m.conversation_id == ^conversation_id and m.inserted_at > ^cursor
    )
  end

  # Distinguished by presence, not by clock: `messages.inserted_at` is second-precision,
  # so two messages written in one test would share a timestamp and prove nothing.
  test "each conversation in a batch gets its own cursor" do
    spoken = insert(:conversation_schema)
    speaker = insert(:participant_schema, conversation_id: spoken.id)
    silent = insert(:conversation_schema)
    user = KlassHero.AccountsFixtures.user_fixture()

    message = insert(:message_schema, conversation_id: spoken.id, sender_id: speaker.user_id)

    assert {:ok, _} = Messaging.add_user_to_conversations(user.id, [spoken.id, silent.id])

    assert {:ok, %{last_read_at: cursor}} = Messaging.get_participant(spoken.id, user.id)
    assert cursor == message.inserted_at

    assert {:ok, %{last_read_at: nil}} = Messaging.get_participant(silent.id, user.id)
  end

  # Rejoining is joining: someone re-added was not entitled to the conversation while
  # away, so what happened in the meantime is history, not a backlog.
  test "re-activating a departed participant re-stamps the cursor", ctx do
    departed_at = ~U[2026-01-01 00:00:00Z]

    participant =
      insert(:participant_schema, conversation_id: ctx.conversation.id, user_id: ctx.user.id)

    Repo.update_all(from(p in Participant, where: p.id == ^participant.id),
      set: [last_read_at: departed_at, left_at: departed_at]
    )

    missed = insert(:message_schema, conversation_id: ctx.conversation.id, sender_id: ctx.speaker.user_id)

    assert {:ok, _} = Messaging.add_user_to_conversations(ctx.user.id, [ctx.conversation.id])

    assert {:ok, %{last_read_at: cursor, left_at: nil}} =
             Messaging.get_participant(ctx.conversation.id, ctx.user.id)

    assert cursor == missed.inserted_at
  end
end
