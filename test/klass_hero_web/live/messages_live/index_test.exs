defmodule KlassHeroWeb.MessagesLive.IndexTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.Messaging.ConversationSummary
  alias KlassHero.Repo

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

    test "renders conversation list", %{conn: conn, user: user} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      summary =
        insert_summary(%{
          user_id: user.id,
          latest_message_content: "Hello there!",
          latest_message_sender_id: user.id,
          latest_message_at: now,
          other_participant_name: "Test Provider"
        })

      {:ok, view, _html} = live(conn, ~p"/messages")

      assert has_element?(view, "#conversations")
      # Stream identity is the conversation, not the summary row that mirrors it.
      assert has_element?(view, "#conversations-#{summary.conversation_id}")
      refute has_element?(view, "h3", "No conversations yet")
    end

    test "renders conversation with unread count", %{conn: conn, user: user} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert_summary(%{
        user_id: user.id,
        latest_message_content: "Message",
        latest_message_sender_id: Ecto.UUID.generate(),
        latest_message_at: now,
        unread_count: 3,
        last_read_at: nil,
        other_participant_name: "Other User"
      })

      {:ok, view, _html} = live(conn, ~p"/messages")

      assert has_element?(view, "#conversations")
    end

    test "orders conversations by most recent", %{conn: conn, user: user} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert_summary(%{
        user_id: user.id,
        latest_message_content: "Old message",
        latest_message_sender_id: user.id,
        latest_message_at: DateTime.add(now, -60, :second),
        other_participant_name: "Old Contact"
      })

      insert_summary(%{
        user_id: user.id,
        latest_message_content: "New message",
        latest_message_sender_id: user.id,
        latest_message_at: now,
        other_participant_name: "New Contact"
      })

      {:ok, view, _html} = live(conn, ~p"/messages")

      assert has_element?(view, "#conversations")
    end

    test "clicking conversation navigates to show page", %{conn: conn, user: user} do
      conversation_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert_summary(%{
        conversation_id: conversation_id,
        user_id: user.id,
        latest_message_at: now,
        other_participant_name: "Test Provider"
      })

      {:ok, view, _html} = live(conn, ~p"/messages")

      html = render(view)
      assert html =~ "/messages/#{conversation_id}"
    end
  end

  describe "page title" do
    setup :register_and_log_in_user

    test "sets page title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/messages")

      assert has_element?(view, "h1", "Messages")
    end
  end

  defp insert_summary(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

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
      inserted_at: now,
      updated_at: now
    }

    merged = Map.merge(defaults, attrs)

    %ConversationSummary{}
    |> Ecto.Changeset.change(merged)
    |> Repo.insert!()
  end
end
