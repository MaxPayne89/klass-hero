defmodule KlassHeroWeb.Flows.AdminConversationMonitoringTest do
  @moduledoc """
  Flow tests for admin conversation monitoring (#744).

  The load-bearing assertions here are the negative ones. Monitoring is read-only,
  and "read-only" is not a property of the context alone — it is a property of what
  the page renders. If a future change reuses `conversation_show/1` or the
  `MessagingLiveHelper, :show` macro on this surface, the composer comes back with
  it, and `refute_has("#message-input")` is what notices.
  """

  use KlassHeroWeb.FlowCase, async: false

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging

  setup do
    provider_user = user_fixture(%{intended_roles: [:provider]})
    provider = insert(:provider_profile_schema, identity_id: provider_user.id, business_name: "Bouldering Bees")

    parent_user = user_fixture(%{intended_roles: [:parent]})
    insert(:parent_profile_schema, identity_id: parent_user.id)

    provider_scope = provider_user |> Scope.for_user() |> Scope.resolve_roles()

    conversation =
      with_real_outbox(fn ->
        {:ok, conversation} =
          Messaging.create_direct_conversation(provider_scope, provider.id, parent_user.id)

        {:ok, _} =
          Messaging.send_message(conversation.id, parent_user.id, "Concern about pickup time")

        conversation
      end)

    %{
      admin: user_fixture(%{is_admin: true}),
      parent_user: parent_user,
      provider: provider,
      conversation: conversation
    }
  end

  describe "access" do
    test "a parent cannot reach the monitoring index", %{parent_user: parent_user} do
      build_conn()
      |> log_in_user(parent_user)
      |> visit(~p"/admin/messages")
      |> assert_path(~p"/")
    end

    test "a parent cannot reach a thread they are not looking at as a participant", %{
      parent_user: parent_user,
      conversation: conversation
    } do
      build_conn()
      |> log_in_user(parent_user)
      |> visit(~p"/admin/messages/#{conversation.id}")
      |> assert_path(~p"/")
    end
  end

  describe "the index" do
    test "lists conversations with their provider, across providers", %{
      admin: admin,
      conversation: conversation
    } do
      other = insert(:conversation_schema)

      build_conn()
      |> log_in_user(admin)
      |> visit(~p"/admin/messages")
      |> assert_has("[data-role=conversation-row]", text: "Bouldering Bees")
      |> assert_has("a[href='/admin/messages/#{conversation.id}']")
      |> assert_has("a[href='/admin/messages/#{other.id}']")
    end

    test "filters to one provider", %{admin: admin, conversation: conversation, provider: provider} do
      other = insert(:conversation_schema)

      build_conn()
      |> log_in_user(admin)
      |> visit(~p"/admin/messages?provider_id=#{provider.id}")
      |> assert_has("a[href='/admin/messages/#{conversation.id}']")
      |> refute_has("a[href='/admin/messages/#{other.id}']")
    end

    test "shows an empty state when nothing matches", %{admin: admin} do
      build_conn()
      |> log_in_user(admin)
      |> visit(~p"/admin/messages?provider_id=#{Ecto.UUID.generate()}")
      |> assert_has("#conversations-empty-state")
    end

    test "opens a thread from the list", %{admin: admin, conversation: conversation} do
      build_conn()
      |> log_in_user(admin)
      |> visit(~p"/admin/messages")
      |> click_link("a[href='/admin/messages/#{conversation.id}']", "Bouldering Bees")
      |> assert_has("[data-role=message]", text: "Concern about pickup time")
    end
  end

  describe "the thread" do
    test "renders messages of a conversation the admin is not a participant of", %{
      admin: admin,
      conversation: conversation
    } do
      refute Messaging.participant?(conversation.id, admin.id)

      build_conn()
      |> log_in_user(admin)
      |> visit(~p"/admin/messages/#{conversation.id}")
      |> assert_has("[data-role=conversation-thread]")
      |> assert_has("[data-role=message]", text: "Concern about pickup time")
    end

    test "renders no composer, no send button and no reply action", %{
      admin: admin,
      conversation: conversation
    } do
      build_conn()
      |> log_in_user(admin)
      |> visit(~p"/admin/messages/#{conversation.id}")
      |> refute_has("#message-input")
      |> refute_has("[data-role=send-message-btn]")
      |> refute_has("textarea")
    end

    test "viewing a thread seats no participant and disturbs no read receipt", %{
      admin: admin,
      conversation: conversation,
      parent_user: parent_user
    } do
      {:ok, participant} = Messaging.get_participant(conversation.id, parent_user.id)
      last_read_at = participant.last_read_at

      build_conn()
      |> log_in_user(admin)
      |> visit(~p"/admin/messages/#{conversation.id}")
      |> assert_has("[data-role=conversation-thread]")

      refute Messaging.participant?(conversation.id, admin.id)

      {:ok, after_view} = Messaging.get_participant(conversation.id, parent_user.id)
      assert after_view.last_read_at == last_read_at
    end

    test "an unknown conversation returns to the index", %{admin: admin} do
      build_conn()
      |> log_in_user(admin)
      |> visit(~p"/admin/messages/#{Ecto.UUID.generate()}")
      |> assert_path(~p"/admin/messages")
    end

    test "a malformed id returns to the index", %{admin: admin} do
      build_conn()
      |> log_in_user(admin)
      |> visit(~p"/admin/messages/not-a-uuid")
      |> assert_path(~p"/admin/messages")
    end
  end
end
