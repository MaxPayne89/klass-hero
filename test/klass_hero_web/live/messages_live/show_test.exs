defmodule KlassHeroWeb.MessagesLive.ShowTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.AccountsFixtures

  describe "authentication" do
    test "requires authentication", %{conn: conn} do
      conversation = insert(:conversation_schema)

      assert {:error, redirect} = live(conn, ~p"/messages/#{conversation.id}")
      assert {:redirect, %{to: path}} = redirect
      assert path =~ "/users/log-in"
    end
  end

  describe "access control" do
    setup :register_and_log_in_user

    test "redirects when conversation not found", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/messages", flash: flash}}} =
               live(conn, ~p"/messages/#{Ecto.UUID.generate()}")

      assert flash["error"] == "Conversation not found"
    end

    test "redirects when not participant", %{conn: conn} do
      conversation = insert(:conversation_schema)

      assert {:error, {:live_redirect, %{to: "/messages", flash: flash}}} =
               live(conn, ~p"/messages/#{conversation.id}")

      assert flash["error"] == "You don't have access to this conversation"
    end
  end

  describe "conversation view" do
    setup :register_and_log_in_user

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

      {:ok, view, _html} = live(conn, ~p"/messages/#{conversation.id}")

      assert has_element?(view, "#messages")
      assert has_element?(view, "#message-form")
    end

    test "renders empty state when no messages", %{conn: conn, user: user} do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/messages/#{conversation.id}")

      assert has_element?(view, "h3", "No messages yet")
    end

    test "renders back navigation link", %{conn: conn, user: user} do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/messages/#{conversation.id}")

      html = render(view)
      assert html =~ "/messages"
    end

    test "autofocuses the message composer on mount", %{conn: conn, user: user} do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, _view, html} = live(conn, ~p"/messages/#{conversation.id}")

      doc = LazyHTML.from_fragment(html)
      textarea = LazyHTML.query(doc, "#message-input")
      assert Enum.count(textarea) == 1
      assert [mounted] = LazyHTML.attribute(textarea, "phx-mounted")
      assert mounted =~ "focus"
    end
  end

  describe "sending messages" do
    setup :register_and_log_in_user

    test "send_message event sends message", %{conn: conn, user: user} do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/messages/#{conversation.id}")

      view
      |> form("#message-form", %{"content" => "Hello from test!"})
      |> render_submit()

      {:ok, messages, _} =
        KlassHero.Messaging.list_messages_for_conversation(conversation.id, limit: 10)

      assert length(messages) == 1
      assert hd(messages).content == "Hello from test!"
    end

    test "ignores empty messages", %{conn: conn, user: user} do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/messages/#{conversation.id}")

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

      {:ok, view, _html} = live(conn, ~p"/messages/#{conversation.id}")

      view
      |> form("#message-form", %{"content" => "Hello!"})
      |> render_submit()

      assert_push_event(view, "clear_message_input", %{})

      # Scoped to the input, not the page: the sender's own view streams the
      # message back over PubSub, so "Hello!" is legitimately on the page.
      refute render(view) |> LazyHTML.from_fragment() |> LazyHTML.filter("#message-input") |> LazyHTML.text() =~
               "Hello!"
    end
  end

  describe "broadcast conversations" do
    setup :register_and_log_in_user

    test "shows broadcast badge for program broadcast", %{conn: conn, user: user} do
      conversation = insert(:broadcast_conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/messages/#{conversation.id}")

      assert has_element?(view, "span", "Broadcast")
    end

    test "shows reply bar instead of message form for parent", %{conn: conn, user: user} do
      provider_user = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: provider_user.id)
      program = insert(:program_schema)

      broadcast =
        insert(:conversation_schema,
          type: "program_broadcast",
          provider_id: provider.id,
          program_id: program.id,
          subject: "Update"
        )

      insert(:participant_schema,
        conversation_id: broadcast.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/messages/#{broadcast.id}")

      assert has_element?(view, "#broadcast-reply-bar")
      refute has_element?(view, "#message-form")
      assert has_element?(view, "button", "Reply privately")
    end

    test "shows message form for direct conversations", %{conn: conn, user: user} do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/messages/#{conversation.id}")

      assert has_element?(view, "#message-form")
      refute has_element?(view, "#broadcast-reply-bar")
    end

    test "reply_privately navigates to direct conversation", %{conn: conn, user: user} do
      provider_user = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: provider_user.id)
      program = insert(:program_schema)

      broadcast =
        insert(:conversation_schema,
          type: "program_broadcast",
          provider_id: provider.id,
          program_id: program.id,
          subject: "Update"
        )

      insert(:participant_schema,
        conversation_id: broadcast.id,
        user_id: user.id
      )

      # Also add provider as participant (as BroadcastToProgram would)
      insert(:participant_schema,
        conversation_id: broadcast.id,
        user_id: provider_user.id
      )

      {:ok, view, _html} = live(conn, ~p"/messages/#{broadcast.id}")

      view
      |> element("#broadcast-reply-bar button", "Reply privately")
      |> render_click()

      # Should navigate to a new direct conversation
      {path, _flash} = assert_redirect(view)
      assert path =~ "/messages/"
    end
  end

  # #1348: a parent re-reading a thread must see the conversation they saw a month
  # ago. Attribution used to be a live staffing lookup, so a staff member leaving
  # restyled every message they had ever sent.
  describe "provider-side attribution" do
    setup :register_and_log_in_user

    setup %{conn: conn, user: user} do
      provider_user = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: provider_user.id)
      program = insert(:program_schema, provider_id: provider.id)
      staff_user = AccountsFixtures.user_fixture()

      staff =
        insert(:staff_member_schema,
          provider_id: provider.id,
          user_id: staff_user.id,
          active: true
        )

      conversation =
        insert(:conversation_schema,
          type: "program_broadcast",
          provider_id: provider.id,
          program_id: program.id,
          subject: "Update"
        )

      for participant_id <- [user.id, staff_user.id] do
        insert(:participant_schema, conversation_id: conversation.id, user_id: participant_id)
      end

      %{conn: conn, conversation: conversation, staff: staff, staff_user: staff_user}
    end

    test "survives the sender's deactivation", ctx do
      {:ok, message} =
        KlassHero.Messaging.send_message(ctx.conversation.id, ctx.staff_user.id, "While employed")

      {:ok, _} = KlassHero.Provider.deactivate_staff_member(ctx.staff)

      {:ok, view, _html} = live(ctx.conn, ~p"/messages/#{ctx.conversation.id}")

      assert has_element?(view, "#messages-#{message.id}-attribution[data-provider-side='true']")
    end

    # Rows written before `sender_role` existed fall back to the live set, which is
    # why that set asks about employment *ever* rather than employment *now*.
    test "holds for a pre-#1348 message with no recorded role", ctx do
      {:ok, message} =
        KlassHero.Messaging.create_message(%{
          conversation_id: ctx.conversation.id,
          sender_id: ctx.staff_user.id,
          content: "Sent before the column existed"
        })

      assert message.sender_role == nil
      {:ok, _} = KlassHero.Provider.deactivate_staff_member(ctx.staff)

      {:ok, view, _html} = live(ctx.conn, ~p"/messages/#{ctx.conversation.id}")

      assert has_element?(view, "#messages-#{message.id}-attribution[data-provider-side='true']")
    end

    test "is absent for a message from another parent", ctx do
      other_parent = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: ctx.conversation.id,
        user_id: other_parent.id
      )

      {:ok, message} =
        KlassHero.Messaging.create_message(%{
          conversation_id: ctx.conversation.id,
          sender_id: other_parent.id,
          content: "Just a parent"
        })

      {:ok, view, _html} = live(ctx.conn, ~p"/messages/#{ctx.conversation.id}")

      assert has_element?(view, "#messages-#{message.id}-attribution[data-provider-side='false']")
    end
  end

  describe "page title" do
    setup :register_and_log_in_user

    test "sets page title to Conversation for direct messages", %{conn: conn, user: user} do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/messages/#{conversation.id}")

      assert has_element?(view, "h1", "Conversation")
    end

    test "sets page title to subject for broadcast with subject", %{conn: conn, user: user} do
      conversation = insert(:broadcast_conversation_schema, subject: "Important Update")

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/messages/#{conversation.id}")

      assert has_element?(view, "h1", "Important Update")
    end
  end

  describe "sending messages with attachments" do
    setup :register_and_log_in_user

    test "sends message with photo attachment", %{conn: conn, user: user} do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/messages/#{conversation.id}")

      photo =
        file_input(view, "#message-form", :attachments, [
          %{
            name: "test_photo.jpg",
            content: <<137, 80, 78, 71, 13, 10, 26, 10>>,
            type: "image/jpeg"
          }
        ])

      render_upload(photo, "test_photo.jpg")

      view
      |> form("#message-form", %{"content" => "Check this out!"})
      |> render_submit()

      {:ok, messages, _} =
        KlassHero.Messaging.list_messages_for_conversation(conversation.id, limit: 10)

      assert length(messages) == 1
      assert hd(messages).content == "Check this out!"
    end

    test "sends photo-only message without text", %{conn: conn, user: user} do
      conversation = insert(:conversation_schema)

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, view, _html} = live(conn, ~p"/messages/#{conversation.id}")

      photo =
        file_input(view, "#message-form", :attachments, [
          %{
            name: "photo.jpg",
            content: <<137, 80, 78, 71, 13, 10, 26, 10>>,
            type: "image/jpeg"
          }
        ])

      render_upload(photo, "photo.jpg")

      view
      |> form("#message-form", %{"content" => ""})
      |> render_submit()

      {:ok, messages, _} =
        KlassHero.Messaging.list_messages_for_conversation(conversation.id, limit: 10)

      assert length(messages) == 1
      assert hd(messages).content == nil
    end
  end
end
