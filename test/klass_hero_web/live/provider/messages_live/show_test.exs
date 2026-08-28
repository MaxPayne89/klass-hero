defmodule KlassHeroWeb.Provider.MessagesLive.ShowTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  describe "authentication and authorization" do
    test "requires authentication", %{conn: conn} do
      conversation = insert(:conversation_schema)

      assert {:error, redirect} = live(conn, ~p"/provider/messages/#{conversation.id}")
      assert {:redirect, %{to: path}} = redirect
      assert path =~ "/users/log-in"
    end

    test "requires provider role", %{conn: conn} do
      conversation = insert(:conversation_schema)
      %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      assert {:error, redirect} = live(conn, ~p"/provider/messages/#{conversation.id}")
      assert {:redirect, %{to: path}} = redirect
      assert path == "/"
    end
  end

  describe "access control" do
    setup :register_and_log_in_provider

    test "redirects when conversation not found", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/provider/messages", flash: flash}}} =
               live(conn, ~p"/provider/messages/#{Ecto.UUID.generate()}")

      assert flash["error"] == "Conversation not found"
    end

    test "redirects when not participant", %{conn: conn} do
      conversation = insert(:conversation_schema)

      assert {:error, {:live_redirect, %{to: "/provider/messages", flash: flash}}} =
               live(conn, ~p"/provider/messages/#{conversation.id}")

      assert flash["error"] == "You don't have access to this conversation"
    end
  end

  describe "conversation view" do
    setup :register_and_log_in_provider

    test "renders conversation with messages", %{conn: conn, user: user} do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, _msg} =
        KlassHero.Messaging.create_message(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "Hello world!"
        })

      {:ok, view, _html} = live(conn, ~p"/provider/messages/#{conversation.id}")

      assert has_element?(view, "#messages")
      assert has_element?(view, "#message-form")
    end

    test "renders empty state when no messages", %{conn: conn, user: user} do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/provider/messages/#{conversation.id}")

      assert has_element?(view, "h3", "No messages yet")
    end

    test "renders the off-platform safety notice with provider wording", %{
      conn: conn,
      user: user
    } do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/provider/messages/#{conversation.id}")

      assert has_element?(view, "[data-role='safety-notice']", "conversations with families")
    end

    test "renders back navigation to provider messages", %{conn: conn, user: user} do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/provider/messages/#{conversation.id}")

      html = render(view)
      assert html =~ "/provider/messages"
    end
  end

  describe "sending messages" do
    setup :register_and_log_in_provider

    test "send_message event sends message", %{conn: conn, user: user} do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/provider/messages/#{conversation.id}")

      view
      |> form("#message-form", %{"content" => "Hello from provider!"})
      |> render_submit()

      {:ok, messages, _} =
        KlassHero.Messaging.list_messages_for_conversation(conversation.id, limit: 10)

      assert length(messages) == 1
      assert hd(messages).content == "Hello from provider!"
    end

    test "ignores empty messages", %{conn: conn, user: user} do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/provider/messages/#{conversation.id}")

      view
      |> form("#message-form", %{"content" => "   "})
      |> render_submit()

      {:ok, messages, _} =
        KlassHero.Messaging.list_messages_for_conversation(conversation.id, limit: 10)

      assert messages == []
    end

    test "clears input after sending", %{conn: conn, user: user} do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/provider/messages/#{conversation.id}")

      view
      |> form("#message-form", %{"content" => "Hello from provider!"})
      |> render_submit()

      assert_push_event(view, "clear_message_input", %{})

      # Scoped to the input, not the page: the sender's own view streams the
      # message back over PubSub, so the content is legitimately on the page.
      refute render(view) |> LazyHTML.from_fragment() |> LazyHTML.filter("#message-input") |> LazyHTML.text() =~
               "Hello from provider!"
    end
  end

  describe "broadcast conversations" do
    setup :register_and_log_in_provider

    test "shows broadcast badge for program broadcast", %{conn: conn, user: user} do
      conversation = insert(:broadcast_conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/provider/messages/#{conversation.id}")

      assert has_element?(view, "span", "Broadcast")
    end

    test "shows message form (not reply bar) for provider on broadcast", %{conn: conn, user: user} do
      conversation = insert(:broadcast_conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/provider/messages/#{conversation.id}")

      assert has_element?(view, "#message-form")
      refute has_element?(view, "#broadcast-reply-bar")
    end
  end
end
