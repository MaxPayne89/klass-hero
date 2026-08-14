defmodule KlassHero.Messaging.ListConversationsTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.ConversationSummary
  alias KlassHero.Messaging.ListConversations
  alias KlassHero.Repo

  defp insert_summary(attrs) do
    defaults = %{
      id: Ecto.UUID.generate(),
      conversation_id: Ecto.UUID.generate(),
      user_id: Ecto.UUID.generate(),
      conversation_type: :direct,
      provider_id: Ecto.UUID.generate(),
      program_id: nil,
      subject: nil,
      other_participant_name: "Other User",
      participant_count: 2,
      latest_message_content: nil,
      latest_message_sender_id: nil,
      latest_message_at: nil,
      unread_count: 0,
      last_read_at: nil,
      archived_at: nil,
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    merged = Map.merge(defaults, attrs)

    %ConversationSummary{}
    |> Ecto.Changeset.change(merged)
    |> Repo.insert!()
  end

  describe "execute/2" do
    test "returns enriched conversations for user" do
      user = AccountsFixtures.user_fixture()
      conversation_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert_summary(%{
        user_id: user.id,
        conversation_id: conversation_id,
        latest_message_content: "Hello!",
        latest_message_sender_id: user.id,
        latest_message_at: now,
        unread_count: 0
      })

      assert {:ok, conversations, has_more} = ListConversations.execute(user.id)

      assert length(conversations) == 1
      refute has_more

      enriched = hd(conversations)
      assert enriched.conversation.id == conversation_id
      assert enriched.conversation.type == :direct
      assert is_integer(enriched.unread_count)
      assert enriched.latest_message != nil
      assert enriched.latest_message.content == "Hello!"
    end

    test "returns unread_count correctly" do
      user = AccountsFixtures.user_fixture()
      other_user_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert_summary(%{
        user_id: user.id,
        latest_message_content: "Message",
        latest_message_sender_id: other_user_id,
        latest_message_at: now,
        unread_count: 3,
        last_read_at: nil
      })

      {:ok, conversations, _has_more} = ListConversations.execute(user.id)

      enriched = hd(conversations)
      assert enriched.unread_count == 3
    end

    test "returns nil latest_message when no messages" do
      user = AccountsFixtures.user_fixture()

      insert_summary(%{
        user_id: user.id,
        latest_message_content: nil,
        latest_message_sender_id: nil,
        latest_message_at: nil
      })

      {:ok, conversations, _has_more} = ListConversations.execute(user.id)

      enriched = hd(conversations)
      assert is_nil(enriched.latest_message)
    end

    test "includes other_participant_name for direct conversations" do
      user = AccountsFixtures.user_fixture()

      insert_summary(%{
        user_id: user.id,
        other_participant_name: "Jane Smith"
      })

      {:ok, conversations, _has_more} = ListConversations.execute(user.id)

      enriched = hd(conversations)
      assert enriched.other_participant_name == "Jane Smith"
    end

    test "respects pagination limit" do
      user = AccountsFixtures.user_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for i <- 1..5 do
        insert_summary(%{
          user_id: user.id,
          latest_message_at: DateTime.add(now, i, :second)
        })
      end

      {:ok, conversations, has_more} = ListConversations.execute(user.id, limit: 3)

      assert length(conversations) == 3
      assert has_more
    end

    test "returns empty list when user has no conversations" do
      user = AccountsFixtures.user_fixture()

      {:ok, conversations, has_more} = ListConversations.execute(user.id)

      assert conversations == []
      refute has_more
    end

    test "excludes archived conversations" do
      user = AccountsFixtures.user_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      active_conv_id = Ecto.UUID.generate()

      insert_summary(%{
        user_id: user.id,
        archived_at: now,
        latest_message_at: now
      })

      insert_summary(%{
        user_id: user.id,
        conversation_id: active_conv_id,
        latest_message_at: DateTime.add(now, 1, :second)
      })

      {:ok, conversations, _has_more} = ListConversations.execute(user.id)

      assert length(conversations) == 1
      assert hd(conversations).conversation.id == active_conv_id
    end
  end
end
