defmodule KlassHero.Messaging.GetTotalUnreadCountTest do
  @moduledoc """
  The nav badge's counter, read live from the write model.

  Every case here seeds real conversations, participants and messages. The previous
  version of this file hand-built `ConversationSummary` rows and asserted their
  `unread_count` back, which could only ever restate the fixture — and did, for the
  whole lifetime of #1513.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging
  alias KlassHero.Messaging.GetTotalUnreadCount
  alias KlassHero.Repo

  setup do
    %{user: AccountsFixtures.user_fixture()}
  end

  describe "execute/1" do
    test "is 0 for a user in no conversations", %{user: user} do
      assert GetTotalUnreadCount.execute(user.id) == 0
    end

    test "counts messages from others across conversations", %{user: user} do
      seed_unread(user, 2)
      seed_unread(user, 3)

      assert GetTotalUnreadCount.execute(user.id) == 5
    end

    test "counts nothing once the cursor is past every message", %{user: user} do
      conversation = seed_unread(user, 2)
      {:ok, _} = Messaging.mark_as_read(conversation.id, user.id)

      assert GetTotalUnreadCount.execute(user.id) == 0
    end

    test "counts only what arrived after the cursor", %{user: user} do
      # The cursor is placed between the two messages rather than by `mark_as_read/2`,
      # which stamps `utc_now()` — at second granularity that lands in the same second
      # as a message inserted right after it, and `>` then reads false.
      conversation = seed_unread(user, 1, seconds_ago: 600)
      insert_message(conversation, AccountsFixtures.user_fixture(), seconds_ago: 60)

      {:ok, _} =
        Messaging.mark_participant_read(
          conversation.id,
          user.id,
          DateTime.add(now(), -300, :second)
        )

      assert GetTotalUnreadCount.execute(user.id) == 1
    end

    test "excludes messages the user sent themselves", %{user: user} do
      # #1513's other half. SendMessage stamps the sender's own cursor after the
      # insert, outside the transaction, best-effort — so a badge relying on that
      # write to hide own messages counts them whenever it fails.
      conversation = insert(:conversation_schema)
      insert(:participant_schema, conversation_id: conversation.id, user_id: user.id)
      insert_message(conversation, user)

      assert GetTotalUnreadCount.execute(user.id) == 0
    end

    test "excludes soft-deleted messages", %{user: user} do
      # #1513 itself: the badge announced mail the reader could not open.
      conversation = seed_unread(user, 1)
      insert_message(conversation, AccountsFixtures.user_fixture(), deleted_at: now())

      assert GetTotalUnreadCount.execute(user.id) == 1
    end

    test "excludes archived conversations", %{user: user} do
      user
      |> seed_unread(4)
      |> Ecto.Changeset.change(archived_at: now())
      |> Repo.update!()

      assert GetTotalUnreadCount.execute(user.id) == 0
    end

    test "excludes conversations the user has left", %{user: user} do
      conversation = insert(:conversation_schema)

      participant =
        insert(:participant_schema, conversation_id: conversation.id, user_id: user.id)

      insert_message(conversation, AccountsFixtures.user_fixture())

      participant
      |> Ecto.Changeset.change(left_at: now())
      |> Repo.update!()

      assert GetTotalUnreadCount.execute(user.id) == 0
    end
  end

  describe "agreement with the inbox" do
    test "the total equals the sum of the badges rendered beneath it", %{user: user} do
      # The property the projection could not state: its total and its per-card counts
      # were computed by different code, so they were free to disagree — and did.
      seed_unread(user, 2)
      seed_unread(user, 1)
      own = seed_unread(user, 1)
      insert_message(own, user)
      insert_message(own, AccountsFixtures.user_fixture(), deleted_at: now())

      {:ok, conversations, false} = Messaging.list_conversations(user.id)
      page_total = conversations |> Enum.map(& &1.unread_count) |> Enum.sum()

      assert GetTotalUnreadCount.execute(user.id) == page_total
      assert page_total == 4
    end
  end

  defp seed_unread(user, message_count, opts \\ []) do
    conversation = insert(:conversation_schema)
    insert(:participant_schema, conversation_id: conversation.id, user_id: user.id)
    sender = AccountsFixtures.user_fixture()

    for _ <- 1..message_count, do: insert_message(conversation, sender, opts)

    conversation
  end

  defp insert_message(conversation, sender, opts \\ []) do
    insert(:message_schema,
      conversation_id: conversation.id,
      sender_id: sender.id,
      deleted_at: Keyword.get(opts, :deleted_at),
      inserted_at: DateTime.add(now(), -Keyword.get(opts, :seconds_ago, 60), :second)
    )
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
