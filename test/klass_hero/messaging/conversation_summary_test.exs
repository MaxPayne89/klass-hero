defmodule KlassHero.Messaging.ConversationSummaryTest do
  @moduledoc """
  Covers what still reads the `conversation_summaries` table through the public
  `KlassHero.Messaging` API: conversation context.

  Two describe blocks left when their reads did. The inbox listing moved to
  `KlassHero.Messaging.ListConversationsTest`, the unread total to
  `KlassHero.Messaging.GetTotalUnreadCountTest` — in both cases the old cases seeded
  rows here and asserted them back, which cannot fail on a read derived from the
  write model.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Messaging
  alias KlassHero.Messaging.ConversationSummary

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
end
