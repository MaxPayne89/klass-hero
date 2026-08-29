defmodule KlassHeroWeb.Provider.MessagesLive.IndexTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

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

    test "renders conversation list", %{conn: conn, user: user, provider: provider} do
      seed_conversation(user, provider)

      {:ok, view, _html} = live(conn, ~p"/provider/messages")

      assert has_element?(view, "#conversations")
      refute has_element?(view, "h3", "No conversations yet")
    end

    test "clicking conversation navigates to provider show page", %{
      conn: conn,
      user: user,
      provider: provider
    } do
      conversation = seed_conversation(user, provider)

      {:ok, view, _html} = live(conn, ~p"/provider/messages")

      assert render(view) =~ "/provider/messages/#{conversation.id}"
    end
  end

  describe "page title" do
    setup :register_and_log_in_provider

    test "sets page title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/messages")

      assert has_element?(view, "h1", "Messages")
    end
  end

  # Was a hand-rolled `conversation_summaries` row. The inbox reads the write model live
  # (ADR-0023), so what makes a conversation appear is the conversation, a participant
  # row for the viewer, and a message — an INNER lateral join, so a thread with no
  # message is correctly invisible.
  defp seed_conversation(user, provider) do
    other = KlassHero.AccountsFixtures.user_fixture()

    # `conversations_principals_ordered` makes the pair canonical, so a direct thread has
    # exactly one representation. Sorting here is not cosmetic — an unsorted pair raises.
    [principal_a, principal_b] = Enum.sort([user.id, other.id])

    conversation =
      insert(:conversation_schema,
        type: :direct,
        provider_id: provider.id,
        principal_a_id: principal_a,
        principal_b_id: principal_b
      )

    insert(:participant_schema, conversation_id: conversation.id, user_id: user.id)
    insert(:message_schema, conversation_id: conversation.id, sender_id: other.id, content: "Hello there!")

    conversation
  end
end
