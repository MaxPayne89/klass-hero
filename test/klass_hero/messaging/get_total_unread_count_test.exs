defmodule KlassHero.Messaging.GetTotalUnreadCountTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.ConversationSummary
  alias KlassHero.Messaging.GetTotalUnreadCount
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

  describe "execute/1" do
    test "returns 0 for user with no conversations" do
      user = AccountsFixtures.user_fixture()

      assert GetTotalUnreadCount.execute(user.id) == 0
    end

    test "returns 0 for user with all messages read" do
      user = AccountsFixtures.user_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert_summary(%{
        user_id: user.id,
        unread_count: 0,
        last_read_at: now
      })

      assert GetTotalUnreadCount.execute(user.id) == 0
    end

    test "returns correct count of unread messages" do
      user = AccountsFixtures.user_fixture()

      insert_summary(%{
        user_id: user.id,
        unread_count: 3
      })

      assert GetTotalUnreadCount.execute(user.id) == 3
    end

    test "returns correct count across multiple conversations" do
      user = AccountsFixtures.user_fixture()

      # First conversation with 2 unread
      insert_summary(%{
        user_id: user.id,
        unread_count: 2
      })

      # Second conversation with 3 unread
      insert_summary(%{
        user_id: user.id,
        unread_count: 3
      })

      assert GetTotalUnreadCount.execute(user.id) == 5
    end

    test "excludes archived conversations" do
      user = AccountsFixtures.user_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert_summary(%{
        user_id: user.id,
        unread_count: 5,
        archived_at: now
      })

      assert GetTotalUnreadCount.execute(user.id) == 0
    end

    test "counts unread across mix of read and unread conversations" do
      user = AccountsFixtures.user_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Fully read conversation
      insert_summary(%{
        user_id: user.id,
        unread_count: 0,
        last_read_at: now
      })

      # Conversation with unread messages
      insert_summary(%{
        user_id: user.id,
        unread_count: 4
      })

      assert GetTotalUnreadCount.execute(user.id) == 4
    end
  end
end
