defmodule KlassHero.Messaging.ListConversationsTest do
  @moduledoc """
  The inbox read, served live from the write model.

  Every row here is a real conversation, participant and message — there is no
  read table to seed, which is the point: what the inbox shows is derived from
  what was written, so it cannot drift from it.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging

  defp at(offset_seconds) do
    DateTime.utc_now() |> DateTime.add(offset_seconds, :second) |> DateTime.truncate(:second)
  end

  defp conversation_with_message(user, opts) do
    conversation = insert(:conversation_schema, Keyword.get(opts, :conversation, []))

    insert(
      :participant_schema,
      [conversation_id: conversation.id, user_id: user.id] ++ Keyword.get(opts, :participant, [])
    )

    for message <- Keyword.get(opts, :messages, []) do
      insert(:message_schema, [conversation_id: conversation.id] ++ message)
    end

    conversation
  end

  describe "list_conversations/2" do
    setup do
      %{user: AccountsFixtures.user_fixture()}
    end

    test "returns a conversation the user participates in", %{user: user} do
      sender = AccountsFixtures.user_fixture()

      conversation =
        conversation_with_message(user,
          messages: [[sender_id: sender.id, content: "Welcome", inserted_at: at(-60)]]
        )

      assert {:ok, [row], false} = Messaging.list_conversations(user.id)
      assert row.conversation_id == conversation.id
      assert row.latest_message_content == "Welcome"
    end

    test "orders by newest message, not by conversation age", %{user: user} do
      sender = AccountsFixtures.user_fixture()

      older_conversation =
        conversation_with_message(user,
          messages: [[sender_id: sender.id, content: "old thread, new message", inserted_at: at(-10)]]
        )

      newer_conversation =
        conversation_with_message(user,
          messages: [[sender_id: sender.id, content: "new thread, old message", inserted_at: at(-600)]]
        )

      assert {:ok, rows, false} = Messaging.list_conversations(user.id)

      assert Enum.map(rows, & &1.conversation_id) == [
               older_conversation.id,
               newer_conversation.id
             ]
    end

    test "previews the newest message", %{user: user} do
      sender = AccountsFixtures.user_fixture()

      conversation_with_message(user,
        messages: [
          [sender_id: sender.id, content: "first", inserted_at: at(-600)],
          [sender_id: sender.id, content: "latest", inserted_at: at(-10)]
        ]
      )

      assert {:ok, [row], false} = Messaging.list_conversations(user.id)
      assert row.latest_message_content == "latest"
    end

    # The badge stops counting soft-deleted messages (#1513), so the preview beside
    # it must stop showing them too, or the card previews a message the badge
    # refuses to count.
    test "ignores a soft-deleted newest message", %{user: user} do
      sender = AccountsFixtures.user_fixture()

      conversation_with_message(user,
        messages: [
          [sender_id: sender.id, content: "visible", inserted_at: at(-600)],
          [sender_id: sender.id, content: "retracted", inserted_at: at(-10), deleted_at: at(-5)]
        ]
      )

      assert {:ok, [row], false} = Messaging.list_conversations(user.id)
      assert row.latest_message_content == "visible"
    end

    test "excludes archived conversations", %{user: user} do
      sender = AccountsFixtures.user_fixture()

      conversation_with_message(user,
        conversation: [archived_at: at(-60)],
        messages: [[sender_id: sender.id, content: "archived", inserted_at: at(-60)]]
      )

      assert {:ok, [], false} = Messaging.list_conversations(user.id)
    end

    test "excludes conversations the user has left", %{user: user} do
      sender = AccountsFixtures.user_fixture()

      conversation_with_message(user,
        participant: [left_at: at(-30)],
        messages: [[sender_id: sender.id, content: "gone", inserted_at: at(-60)]]
      )

      assert {:ok, [], false} = Messaging.list_conversations(user.id)
    end

    test "excludes a conversation with no messages", %{user: user} do
      conversation_with_message(user, messages: [])

      assert {:ok, [], false} = Messaging.list_conversations(user.id)
    end

    test "excludes a conversation whose only message is soft-deleted", %{user: user} do
      sender = AccountsFixtures.user_fixture()

      conversation_with_message(user,
        messages: [[sender_id: sender.id, content: "retracted", inserted_at: at(-60), deleted_at: at(-5)]]
      )

      assert {:ok, [], false} = Messaging.list_conversations(user.id)
    end

    test "paginates, reporting whether more remain", %{user: user} do
      sender = AccountsFixtures.user_fixture()

      for offset <- 1..3 do
        conversation_with_message(user,
          messages: [[sender_id: sender.id, content: "msg #{offset}", inserted_at: at(-offset * 60)]]
        )
      end

      assert {:ok, rows, true} = Messaging.list_conversations(user.id, limit: 2)
      assert length(rows) == 2

      assert {:ok, all, false} = Messaging.list_conversations(user.id, limit: 10)
      assert length(all) == 3
    end
  end

  describe "list_conversations/2 — unread" do
    setup do
      %{user: AccountsFixtures.user_fixture(), sender: AccountsFixtures.user_fixture()}
    end

    test "counts messages from others that arrived after the last read", ctx do
      conversation_with_message(ctx.user,
        participant: [last_read_at: at(-300)],
        messages: [
          [sender_id: ctx.sender.id, content: "read already", inserted_at: at(-600)],
          [sender_id: ctx.sender.id, content: "new one", inserted_at: at(-60)],
          [sender_id: ctx.sender.id, content: "new two", inserted_at: at(-30)]
        ]
      )

      assert {:ok, [row], false} = Messaging.list_conversations(ctx.user.id)
      assert row.unread_count == 2
    end

    test "counts everything when the participant has never read", ctx do
      conversation_with_message(ctx.user,
        messages: [
          [sender_id: ctx.sender.id, content: "one", inserted_at: at(-60)],
          [sender_id: ctx.sender.id, content: "two", inserted_at: at(-30)]
        ]
      )

      assert {:ok, [row], false} = Messaging.list_conversations(ctx.user.id)
      assert row.unread_count == 2
    end

    test "never counts the reader's own messages", ctx do
      conversation_with_message(ctx.user,
        messages: [
          [sender_id: ctx.sender.id, content: "theirs", inserted_at: at(-60)],
          [sender_id: ctx.user.id, content: "mine", inserted_at: at(-30)]
        ]
      )

      assert {:ok, [row], false} = Messaging.list_conversations(ctx.user.id)
      assert row.unread_count == 1
    end

    test "never counts soft-deleted messages", ctx do
      conversation_with_message(ctx.user,
        messages: [
          [sender_id: ctx.sender.id, content: "kept", inserted_at: at(-60)],
          [sender_id: ctx.sender.id, content: "retracted", inserted_at: at(-30), deleted_at: at(-5)]
        ]
      )

      assert {:ok, [row], false} = Messaging.list_conversations(ctx.user.id)
      assert row.unread_count == 1
    end
  end

  describe "list_conversations/2 — display names" do
    test "names a broadcast after its program, read live" do
      user = AccountsFixtures.user_fixture()
      sender = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id, title: "Swim Club")

      conversation_with_message(user,
        conversation: [type: :program_broadcast, provider_id: provider.id, program_id: program.id],
        messages: [[sender_id: sender.id, content: "Field trip", inserted_at: at(-60)]]
      )

      assert {:ok, [row], false} = Messaging.list_conversations(user.id)
      assert row.program_name == "Swim Club"
      assert row.conversation_type == :program_broadcast
    end

    # #896 by subtraction: nothing stores the title, so a rename cannot go stale.
    test "a renamed program shows its new title with no propagation step" do
      user = AccountsFixtures.user_fixture()
      sender = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id, title: "Old Name")

      conversation_with_message(user,
        conversation: [type: :program_broadcast, provider_id: provider.id, program_id: program.id],
        messages: [[sender_id: sender.id, content: "Field trip", inserted_at: at(-60)]]
      )

      program
      |> Ecto.Changeset.change(title: "New Name")
      |> Repo.update!()

      assert {:ok, [row], false} = Messaging.list_conversations(user.id)
      assert row.program_name == "New Name"
    end

    test "names a direct thread after the other principal" do
      user = AccountsFixtures.user_fixture()
      other = AccountsFixtures.user_fixture(%{name: "Alice Parent"})
      provider = insert(:provider_profile_schema)

      [a, b] = Enum.sort([user.id, other.id])

      conversation =
        conversation_with_message(user,
          conversation: [
            type: :direct,
            provider_id: provider.id,
            principal_a_id: a,
            principal_b_id: b
          ],
          messages: [[sender_id: other.id, content: "Hello", inserted_at: at(-60)]]
        )

      insert(:participant_schema, conversation_id: conversation.id, user_id: other.id)

      assert {:ok, [row], false} = Messaging.list_conversations(user.id)
      assert row.other_participant_name == "Alice Parent"
    end
  end
end
