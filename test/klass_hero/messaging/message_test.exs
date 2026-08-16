defmodule KlassHero.Messaging.MessageTest do
  @moduledoc """
  Covers the flattened Message schema-as-struct: its changesets (the sole validation
  gatekeeper), the Ecto.Enum message_type, and persistence through the public
  `KlassHero.Messaging` API — including the sender-names map and soft-delete/retention paths.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging
  alias KlassHero.Messaging.Message

  describe "create_changeset/2" do
    test "valid with conversation_id and sender_id" do
      changeset =
        Message.create_changeset(%{
          conversation_id: Ecto.UUID.generate(),
          sender_id: Ecto.UUID.generate(),
          content: "hi"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :message_type) == :text
    end

    test "requires conversation_id and sender_id" do
      changeset = Message.create_changeset(%{content: "hi"})

      assert %{conversation_id: ["can't be blank"], sender_id: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "rejects content longer than 10,000 characters" do
      changeset =
        Message.create_changeset(%{
          conversation_id: Ecto.UUID.generate(),
          sender_id: Ecto.UUID.generate(),
          content: String.duplicate("x", 10_001)
        })

      assert %{content: ["should be at most 10000 character(s)"]} = errors_on(changeset)
    end

    test "rejects a message_type outside the enum" do
      changeset =
        Message.create_changeset(%{
          conversation_id: Ecto.UUID.generate(),
          sender_id: Ecto.UUID.generate(),
          message_type: :shout
        })

      assert %{message_type: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects a sender_role outside the enum" do
      changeset =
        Message.create_changeset(%{
          conversation_id: Ecto.UUID.generate(),
          sender_id: Ecto.UUID.generate(),
          sender_role: :landlord
        })

      assert %{sender_role: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "provider_side?/2" do
    @sender_id "11111111-1111-1111-1111-111111111111"
    @other_id "22222222-2222-2222-2222-222222222222"

    # {sender_role, fallback set, expected, why}
    @cases [
      {:provider, nil, true, "the provider owner is provider-side"},
      {:staff, nil, true, "staff are provider-side"},
      {:parent, nil, false, "parents are not"},
      {:parent, [@sender_id], false, "a persisted role wins over the live set"},
      {:staff, [@other_id], true, "a persisted role wins even when the set disagrees"},
      {nil, [@sender_id], true, "pre-#1348 rows fall back to the live set"},
      {nil, [@other_id], false, "fallback says no when the sender is absent"},
      {nil, nil, false, "no role and no set renders plainly"}
    ]

    for {role, ids, expected, why} <- @cases do
      test "#{why} (role: #{inspect(role)})" do
        message = %Message{sender_id: @sender_id, sender_role: unquote(role)}
        fallback = unquote(ids) && MapSet.new(unquote(ids))

        assert Message.provider_side?(message, fallback) == unquote(expected),
               "expected provider_side? to be #{unquote(expected)} because #{unquote(why)}"
      end
    end
  end

  describe "create_message/1" do
    test "persists a message with the enum loaded as an atom" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()
      insert(:participant_schema, conversation_id: conversation.id, user_id: user.id)

      assert {:ok, %Message{} = message} =
               Messaging.create_message(%{
                 conversation_id: conversation.id,
                 sender_id: user.id,
                 content: "Hello!"
               })

      assert message.message_type == :text
      assert {:ok, reloaded} = Messaging.get_message_by_id(message.id)
      assert reloaded.content == "Hello!"
    end
  end

  describe "list_messages_for_conversation/2 and list_messages_with_senders/2" do
    setup do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()
      insert(:participant_schema, conversation_id: conversation.id, user_id: user.id)
      %{conversation: conversation, user: user}
    end

    test "lists non-deleted messages newest first with has_more", %{conversation: conversation, user: user} do
      for i <- 1..3 do
        {:ok, _} =
          Messaging.create_message(%{conversation_id: conversation.id, sender_id: user.id, content: "m#{i}"})
      end

      assert {:ok, messages, true} =
               Messaging.list_messages_for_conversation(conversation.id, limit: 2)

      assert length(messages) == 2
    end

    test "excludes soft-deleted messages", %{conversation: conversation, user: user} do
      {:ok, message} =
        Messaging.create_message(%{conversation_id: conversation.id, sender_id: user.id, content: "bye"})

      {:ok, _} = Messaging.soft_delete_message(message)

      assert {:ok, [], false} = Messaging.list_messages_for_conversation(conversation.id)
    end

    test "builds a sender_id => name map, deduped per sender", %{conversation: conversation, user: user} do
      for _ <- 1..2 do
        {:ok, _} =
          Messaging.create_message(%{conversation_id: conversation.id, sender_id: user.id, content: "hey"})
      end

      assert {:ok, messages, sender_names, false} =
               Messaging.list_messages_with_senders(conversation.id, [])

      assert length(messages) == 2
      assert map_size(sender_names) == 1
      assert Map.has_key?(sender_names, user.id)
    end
  end

  describe "anonymize_messages_for_sender/1 and retention" do
    test "blanks a sender's message content" do
      message = insert(:message_schema, content: "secret")

      assert {:ok, count} = Messaging.anonymize_messages_for_sender(message.sender_id)
      assert count >= 1
      assert {:ok, reloaded} = Messaging.get_message_by_id(message.id)
      assert reloaded.content == "[deleted]"
    end

    test "delete_messages_for_expired_conversations removes messages of expired conversations" do
      conversation =
        insert(:conversation_schema,
          archived_at: DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.truncate(:second),
          retention_until: DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
        )

      user = AccountsFixtures.user_fixture()
      insert(:participant_schema, conversation_id: conversation.id, user_id: user.id)
      {:ok, message} = Messaging.create_message(%{conversation_id: conversation.id, sender_id: user.id, content: "x"})

      future = DateTime.add(DateTime.utc_now(), 60, :day)

      assert {:ok, count, [_ | _]} = Messaging.delete_messages_for_expired_conversations(future)
      assert count >= 1
      assert {:error, :not_found} = Messaging.get_message_by_id(message.id)
    end
  end
end
