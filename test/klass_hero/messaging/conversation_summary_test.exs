defmodule KlassHero.Messaging.ConversationSummaryTest do
  @moduledoc """
  Covers the flattened ConversationSummary read model through the public
  `KlassHero.Messaging` API: listing, unread totals, system-note tokens
  (including the write-through seed fallback), and conversation context.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Messaging

  describe "list_conversation_summaries_for_user/2" do
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

      assert {:ok, [first, second], false} =
               Messaging.list_conversation_summaries_for_user(user_id, [])

      assert first.id == newer.id
      assert second.id == older.id
    end

    test "excludes archived summaries" do
      user_id = Ecto.UUID.generate()
      insert(:conversation_summary_schema, user_id: user_id, archived_at: DateTime.utc_now())

      assert {:ok, [], false} = Messaging.list_conversation_summaries_for_user(user_id, [])
    end

    test "reports has_more via the limit+1 probe" do
      user_id = Ecto.UUID.generate()
      insert_list(3, :conversation_summary_schema, user_id: user_id)

      assert {:ok, items, true} =
               Messaging.list_conversation_summaries_for_user(user_id, limit: 2)

      assert length(items) == 2
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

  describe "has_system_note?/2 and write_system_note_token/2" do
    test "false before, true after stamping a token on existing rows" do
      conversation_id = Ecto.UUID.generate()
      insert(:conversation_summary_schema, conversation_id: conversation_id)

      refute Messaging.has_system_note?(conversation_id, "welcome")
      assert :ok = Messaging.write_system_note_token(conversation_id, "welcome")
      assert Messaging.has_system_note?(conversation_id, "welcome")
    end

    test "seeds summary rows when the projection has not created them yet" do
      conversation = insert(:conversation_schema)
      insert(:participant_schema, conversation_id: conversation.id)

      assert :ok = Messaging.write_system_note_token(conversation.id, "reply-context")
      assert Messaging.has_system_note?(conversation.id, "reply-context")
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
