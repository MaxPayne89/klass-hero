defmodule KlassHero.Messaging.ConversationSummaryTest do
  @moduledoc """
  Covers the flattened ConversationSummary read model through the public
  `KlassHero.Messaging` API: listing, unread totals, system-note tokens
  (including the write-through seed fallback), and conversation context.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Messaging
  alias KlassHero.Messaging.ConversationSummary

  describe "list_conversations/2" do
    test "returns read-table structs, not a reshaped map" do
      user_id = Ecto.UUID.generate()

      summary =
        insert(:conversation_summary_schema,
          user_id: user_id,
          latest_message_content: "Hello!",
          unread_count: 3
        )

      assert {:ok, [%ConversationSummary{} = listed], false} = Messaging.list_conversations(user_id)

      assert listed.conversation_id == summary.conversation_id
      assert listed.conversation_type == :direct
      assert listed.latest_message_content == "Hello!"
      assert listed.unread_count == 3
    end

    test "returns non-archived summaries newest first" do
      user_id = Ecto.UUID.generate()

      older =
        insert(:conversation_summary_schema,
          user_id: user_id,
          latest_message_at: ~U[2025-01-01 10:00:00Z]
        )

      newer =
        insert(:conversation_summary_schema,
          user_id: user_id,
          latest_message_at: ~U[2025-02-01 10:00:00Z]
        )

      assert {:ok, [first, second], false} = Messaging.list_conversations(user_id)

      assert first.id == newer.id
      assert second.id == older.id
    end

    test "excludes archived summaries" do
      user_id = Ecto.UUID.generate()
      insert(:conversation_summary_schema, user_id: user_id, archived_at: DateTime.utc_now())

      assert {:ok, [], false} = Messaging.list_conversations(user_id)
    end

    test "excludes a conversation that has never carried a message" do
      user_id = Ecto.UUID.generate()

      insert(:conversation_summary_schema,
        user_id: user_id,
        latest_message_content: nil,
        latest_message_at: nil,
        has_attachments: false
      )

      assert {:ok, [], false} = Messaging.list_conversations(user_id)
    end

    test "includes an attachments-only conversation, which has no text content" do
      user_id = Ecto.UUID.generate()

      summary =
        insert(:conversation_summary_schema,
          user_id: user_id,
          latest_message_content: nil,
          has_attachments: true
        )

      assert {:ok, [listed], false} = Messaging.list_conversations(user_id)
      assert listed.id == summary.id
    end

    test "reports has_more via the limit+1 probe" do
      user_id = Ecto.UUID.generate()
      insert_list(3, :conversation_summary_schema, user_id: user_id)

      assert {:ok, items, true} = Messaging.list_conversations(user_id, limit: 2)

      assert length(items) == 2
    end
  end

  describe "has_latest_message?/1" do
    # {latest_message_content, has_attachments, expected}
    @latest_message_cases [
      {nil, false, false},
      {nil, true, true},
      {"Hello", false, true},
      {"Hello", true, true}
    ]

    test "is false only when there is neither content nor an attachment" do
      for {content, has_attachments, expected} <- @latest_message_cases do
        summary = %ConversationSummary{
          latest_message_content: content,
          has_attachments: has_attachments
        }

        assert ConversationSummary.has_latest_message?(summary) == expected,
               "content=#{inspect(content)} has_attachments=#{has_attachments} " <>
                 "should be #{expected}"
      end
    end
  end

  describe "summaries_total_unread_count/1" do
    test "sums unread across non-archived summaries" do
      user_id = Ecto.UUID.generate()
      insert(:conversation_summary_schema, user_id: user_id, unread_count: 2)
      insert(:conversation_summary_schema, user_id: user_id, unread_count: 3)
      insert(:conversation_summary_schema, user_id: user_id, unread_count: 5, archived_at: DateTime.utc_now())

      assert Messaging.summaries_total_unread_count(user_id) == 5
    end

    test "returns 0 when the user has no summaries" do
      assert Messaging.summaries_total_unread_count(Ecto.UUID.generate()) == 0
    end
  end

  describe "has_system_note?/2" do
    test "true only once a system message carrying the token exists" do
      conversation = insert(:conversation_schema)

      refute Messaging.has_system_note?(conversation.id, "[broadcast:abc]")

      insert(:message_schema,
        conversation_id: conversation.id,
        message_type: "system",
        content: "[broadcast:abc] Re: Schedule Change"
      )

      assert Messaging.has_system_note?(conversation.id, "[broadcast:abc]")
    end

    test "ignores an ordinary message that happens to quote the token" do
      conversation = insert(:conversation_schema)

      insert(:message_schema,
        conversation_id: conversation.id,
        message_type: "text",
        content: "[broadcast:abc] is what the note said"
      )

      refute Messaging.has_system_note?(conversation.id, "[broadcast:abc]")
    end

    test "does not confuse one broadcast's token with another's" do
      conversation = insert(:conversation_schema)

      insert(:message_schema,
        conversation_id: conversation.id,
        message_type: "system",
        content: "[broadcast:aaa] Re: One"
      )

      refute Messaging.has_system_note?(conversation.id, "[broadcast:bbb]")
    end
  end

  describe "get_conversation_summary_context/2" do
    test "returns the enrolled child names and other-participant name" do
      summary =
        insert(:conversation_summary_schema,
          other_participant_name: "Alice Parent",
          enrolled_child_names: ["Bob", "Cara"]
        )

      assert %{enrolled_child_names: ["Bob", "Cara"], other_participant_name: "Alice Parent"} =
               Messaging.get_conversation_summary_context(summary.conversation_id, summary.user_id)
    end

    test "defaults when no summary row exists" do
      assert %{enrolled_child_names: [], other_participant_name: nil} =
               Messaging.get_conversation_summary_context(Ecto.UUID.generate(), Ecto.UUID.generate())
    end
  end
end
