defmodule KlassHero.Messaging.MonitorConversationsTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.MonitorConversations

  defp admin_scope, do: AccountsFixtures.admin_scope_fixture()

  describe "execute/2 authorization" do
    test "refuses a non-admin scope" do
      insert(:conversation_schema)

      assert {:error, :unauthorized} =
               MonitorConversations.execute(AccountsFixtures.user_scope_fixture())
    end

    test "refuses a non-admin scope even when no conversations exist" do
      assert {:error, :unauthorized} =
               MonitorConversations.execute(AccountsFixtures.user_scope_fixture())
    end
  end

  describe "execute/2 listing" do
    test "lists conversations across different providers" do
      one = insert(:conversation_schema)
      two = insert(:conversation_schema)

      refute one.provider_id == two.provider_id

      assert {:ok, conversations, false} = MonitorConversations.execute(admin_scope())

      ids = Enum.map(conversations, & &1.id)
      assert one.id in ids
      assert two.id in ids
      assert Enum.all?(conversations, &match?(%Conversation{}, &1))
    end

    test "returns conversations the admin is not a participant of" do
      conversation = insert(:conversation_schema)

      assert {:ok, [listed], false} = MonitorConversations.execute(admin_scope())
      assert listed.id == conversation.id
      refute KlassHero.Messaging.participant?(conversation.id, admin_scope().user.id)
    end

    test "filters by provider" do
      wanted = insert(:conversation_schema)
      _other = insert(:conversation_schema)

      assert {:ok, [listed], false} =
               MonitorConversations.execute(admin_scope(), provider_id: wanted.provider_id)

      assert listed.id == wanted.id
    end

    # `participant_schema_factory` inserts a conversation of its own (factory.ex:1443)
    # even when `conversation_id` is overridden, so this asserts on the row it wants
    # rather than on the size of the page.
    test "preloads participants for the list rows" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()
      insert(:participant_schema, conversation_id: conversation.id, user_id: user.id)

      assert {:ok, conversations, false} = MonitorConversations.execute(admin_scope())

      listed = Enum.find(conversations, &(&1.id == conversation.id))
      assert [%{user_id: participant_user_id}] = listed.participants
      assert participant_user_id == user.id
    end
  end

  describe "execute/2 pagination" do
    test "reports has_more when more rows exist than the limit" do
      for _ <- 1..3, do: insert(:conversation_schema)

      assert {:ok, listed, true} = MonitorConversations.execute(admin_scope(), limit: 2)
      assert length(listed) == 2
    end

    test "reports has_more false when the page is the last one" do
      for _ <- 1..2, do: insert(:conversation_schema)

      assert {:ok, listed, false} = MonitorConversations.execute(admin_scope(), limit: 2)
      assert length(listed) == 2
    end

    test "newest first, and :before walks to the older page" do
      older = insert(:conversation_schema, inserted_at: ~N[2026-01-01 10:00:00])
      newer = insert(:conversation_schema, inserted_at: ~N[2026-02-01 10:00:00])

      assert {:ok, [first, second], false} = MonitorConversations.execute(admin_scope())
      assert first.id == newer.id
      assert second.id == older.id

      assert {:ok, [only], false} =
               MonitorConversations.execute(admin_scope(), before: newer.inserted_at)

      assert only.id == older.id
    end
  end
end
