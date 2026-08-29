defmodule KlassHeroWeb.MessagesLive.IndexTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.AccountsFixtures

  describe "authentication" do
    test "requires authentication", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/messages")
      assert {:redirect, %{to: path}} = redirect
      assert path =~ "/users/log-in"
    end
  end

  describe "empty state" do
    setup :register_and_log_in_user

    test "renders empty state when no conversations", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/messages")

      assert has_element?(view, "h3", "No conversations yet")
      assert has_element?(view, "p", "Your conversations with providers will appear here")
    end
  end

  describe "conversation list" do
    setup :register_and_log_in_user

    test "renders a conversation the user participates in", %{conn: conn, user: user} do
      conversation = seed_conversation(user, "Hello there!")

      {:ok, view, _html} = live(conn, ~p"/messages")

      assert has_element?(view, "#conversations")
      assert has_element?(view, "#conversations-#{conversation.id}")
      refute has_element?(view, "h3", "No conversations yet")
    end

    test "badges a message that arrived from someone else", %{conn: conn, user: user} do
      seed_conversation(user, "Message from them")

      {:ok, view, _html} = live(conn, ~p"/messages")

      assert has_element?(view, "[data-role=unread-count]")
    end

    test "orders conversations by their newest message", %{conn: conn, user: user} do
      older = seed_conversation(user, "Old message", seconds_ago: 600)
      newer = seed_conversation(user, "New message", seconds_ago: 10)

      {:ok, view, _html} = live(conn, ~p"/messages")
      html = render(view)

      assert :binary.match(html, newer.id) < :binary.match(html, older.id)
    end

    test "clicking conversation navigates to show page", %{conn: conn, user: user} do
      conversation = seed_conversation(user, "Test message")

      {:ok, view, _html} = live(conn, ~p"/messages")

      assert render(view) =~ "/messages/#{conversation.id}"
    end
  end

  describe "page title" do
    setup :register_and_log_in_user

    test "sets page title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/messages")

      assert has_element?(view, "h1", "Messages")
    end
  end

  # The inbox is derived from the write model, so a fixture here is a real
  # conversation with a real participant and a real message. There is no read
  # table to seed any more, and a seeded row would simply not be read.
  defp seed_conversation(user, content, opts \\ []) do
    sender = AccountsFixtures.user_fixture()
    conversation = insert(:conversation_schema)

    insert(:participant_schema, conversation_id: conversation.id, user_id: user.id)

    insert(:message_schema,
      conversation_id: conversation.id,
      sender_id: sender.id,
      content: content,
      inserted_at:
        DateTime.utc_now()
        |> DateTime.add(-Keyword.get(opts, :seconds_ago, 60), :second)
        |> DateTime.truncate(:second)
    )

    conversation
  end
end
