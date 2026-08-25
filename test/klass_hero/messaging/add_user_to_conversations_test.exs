defmodule KlassHero.Messaging.AddUserToConversationsTest do
  @moduledoc """
  Guards the two branches of `add_user_to_conversations`' upsert.

  The `:last_read_at` option was added for #381's parent back-fill, but the
  function is shared with `StaffAssignmentHandler`. Re-stamping the cursor
  unconditionally would push a NULL over a returning staff member's read state and
  reset their whole thread to unread — a regression with no user-visible symptom
  until someone opens a conversation they had already read.
  """

  use KlassHero.DataCase, async: true

  import Ecto.Query
  import KlassHero.Factory

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Participant
  alias KlassHero.Repo

  @cursor ~U[2026-01-01 00:00:00Z]

  setup do
    conversation = insert(:conversation_schema)
    user = KlassHero.AccountsFixtures.user_fixture()
    participant = insert(:participant_schema, conversation_id: conversation.id, user_id: user.id)

    depart(participant, @cursor)

    %{conversation: conversation, user: user, participant: participant}
  end

  test "the staff path re-activates without touching the read cursor", ctx do
    assert {:ok, _} = Messaging.add_user_to_conversations(ctx.user.id, [ctx.conversation.id])

    assert %{last_read_at: @cursor, left_at: nil} = reload(ctx.participant)
  end

  test "the parent path re-activates and re-stamps the read cursor", ctx do
    rejoined_at = ~U[2026-06-01 00:00:00Z]

    assert {:ok, _} =
             Messaging.add_user_to_conversations(ctx.user.id, [ctx.conversation.id], last_read_at: rejoined_at)

    assert %{last_read_at: ^rejoined_at, left_at: nil} = reload(ctx.participant)
  end

  test "an explicit nil cursor on a fresh join means everything is unread", ctx do
    other = insert(:conversation_schema)

    assert {:ok, _} =
             Messaging.add_user_to_conversations(ctx.user.id, [other.id], last_read_at: nil)

    assert {:ok, %{last_read_at: nil}} = Messaging.get_participant(other.id, ctx.user.id)
  end

  defp depart(participant, at) do
    Repo.update_all(from(p in Participant, where: p.id == ^participant.id),
      set: [last_read_at: at, left_at: at]
    )
  end

  defp reload(participant) do
    Repo.one(
      from p in Participant,
        where: p.id == ^participant.id,
        select: %{last_read_at: p.last_read_at, left_at: p.left_at}
    )
  end
end
