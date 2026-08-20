defmodule KlassHeroWeb.Flows.MessagingConversationListTest do
  @moduledoc """
  Flow tests for the conversation list and its unread badge.

  Migrated from `test/e2e/messaging/conversation_list_test.exs` and
  `mark_as_read_test.exs`. The migration is what makes these assertions mean
  something: in the browser tier they ran `ConversationSummaries.rebuild/0` before
  every read, so they asserted the projection's bootstrap query. Here the rows are
  written by `{ConversationSummaries, :project}` from delivered `message_sent` and
  `messages_read` events — a projection that dropped one would now fail.
  """

  use KlassHeroWeb.FlowCase, async: false

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging

  setup do
    provider_user = user_fixture(%{intended_roles: [:provider]})
    provider = insert(:provider_profile_schema, identity_id: provider_user.id)

    parent_user = user_fixture(%{intended_roles: [:parent]})
    insert(:parent_profile_schema, identity_id: parent_user.id)

    provider_scope = provider_user |> Scope.for_user() |> Scope.resolve_roles()

    conversation =
      with_real_outbox(fn ->
        {:ok, conversation} =
          Messaging.create_direct_conversation(provider_scope, provider.id, parent_user.id)

        {:ok, _} =
          Messaging.send_message(conversation.id, provider_user.id, "Welcome to our program!")

        conversation
      end)

    %{provider_user: provider_user, parent_user: parent_user, conversation: conversation}
  end

  test "the list shows the latest message as the preview", %{
    conn: conn,
    provider_user: provider_user,
    parent_user: parent_user,
    conversation: conversation
  } do
    build_conn()
    |> log_in_user(parent_user)
    |> visit(~p"/messages")
    |> assert_has("[data-role=conversation-card]", text: "Welcome to our program!")

    with_real_outbox(fn ->
      conn
      |> log_in_user(provider_user)
      |> visit(~p"/provider/messages/#{conversation.id}")
      |> fill_in("#message-input", "Message", with: "Class is moved to Room 204 tomorrow")
      |> submit()
    end)

    build_conn()
    |> log_in_user(parent_user)
    |> visit(~p"/messages")
    |> assert_has("[data-role=conversation-card]", text: "Class is moved to Room 204 tomorrow")
  end

  test "opening a conversation clears its unread badge", %{
    conn: conn,
    parent_user: parent_user,
    conversation: conversation
  } do
    build_conn()
    |> log_in_user(parent_user)
    |> visit(~p"/messages")
    |> assert_has("[data-role=unread-count]", text: "1")

    # mark_as_read fires on connected mount; the messages_read event it stages is
    # what clears the badge.
    with_real_outbox(fn ->
      conn
      |> log_in_user(parent_user)
      |> visit(~p"/messages/#{conversation.id}")
      |> assert_has("[data-role=message]", text: "Welcome to our program!")
    end)

    build_conn()
    |> log_in_user(parent_user)
    |> visit(~p"/messages")
    |> refute_has("[data-role=unread-count]")
  end

  # The read is arranged through the facade rather than by opening the thread,
  # because phoenix_test leaves a visited LiveView mounted for the rest of the test
  # — even after navigating away. A mounted thread keeps marking arrivals read (as
  # it should), so a UI-driven read here would prevent the very badge this asserts.
  # "The parent has genuinely closed the tab" is browser-tier territory.
  test "a message that arrives after the parent has left raises the badge again", %{
    provider_user: provider_user,
    parent_user: parent_user,
    conversation: conversation
  } do
    with_real_outbox(fn ->
      Messaging.mark_as_read(conversation.id, parent_user.id)
    end)

    build_conn()
    |> log_in_user(parent_user)
    |> visit(~p"/messages")
    |> refute_has("[data-role=unread-count]")

    with_real_outbox(fn ->
      build_conn()
      |> log_in_user(provider_user)
      |> visit(~p"/provider/messages/#{conversation.id}")
      |> fill_in("#message-input", "Message", with: "New homework assignment posted")
      |> submit()
    end)

    build_conn()
    |> log_in_user(parent_user)
    |> visit(~p"/messages")
    |> assert_has("[data-role=unread-count]", text: "1")
  end
end
