defmodule KlassHeroWeb.Provider.MessagesLive.IndexTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.Messaging.ConversationSummary
  alias KlassHero.Repo

  describe "authentication and authorization" do
    test "requires authentication", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/provider/messages")
      assert {:redirect, %{to: path}} = redirect
      assert path =~ "/users/log-in"
    end

    test "requires provider role", %{conn: conn} do
      # Register as regular user, not provider
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      assert {:error, redirect} = live(conn, ~p"/provider/messages")
      assert {:redirect, %{to: path}} = redirect
      assert path == "/"
    end
  end

  describe "empty state" do
    setup :register_and_log_in_provider

    test "renders empty state when no conversations", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/messages")

      assert has_element?(view, "h3", "No conversations yet")
    end
  end

  describe "conversation list" do
    setup :register_and_log_in_provider

    test "renders conversation list", %{conn: conn, user: user} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert_summary(%{
        user_id: user.id,
        latest_message_content: "Hello there!",
        latest_message_sender_id: user.id,
        latest_message_at: now,
        other_participant_name: "Test Parent"
      })

      {:ok, view, _html} = live(conn, ~p"/provider/messages")

      assert has_element?(view, "#conversations")
      refute has_element?(view, "h3", "No conversations yet")
    end

    test "clicking conversation navigates to provider show page", %{conn: conn, user: user} do
      conversation_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert_summary(%{
        conversation_id: conversation_id,
        user_id: user.id,
        latest_message_at: now,
        other_participant_name: "Test Parent"
      })

      {:ok, view, _html} = live(conn, ~p"/provider/messages")

      html = render(view)
      assert html =~ "/provider/messages/#{conversation_id}"
    end
  end

  describe "page title" do
    setup :register_and_log_in_provider

    test "sets page title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/messages")

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
