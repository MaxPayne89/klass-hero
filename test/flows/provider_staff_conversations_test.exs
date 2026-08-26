defmodule KlassHeroWeb.Flows.ProviderStaffConversationsTest do
  @moduledoc """
  Flow tests for a provider owner reading the threads their staff conduct (#746).

  The load-bearing assertions here are the negative ones, for the same reason they
  are on the admin monitoring surface. "Read-only" is not a property of the context
  alone — it is a property of what the page renders. If a future change reuses
  `conversation_show/1` or the `MessagingLiveHelper, :show` macro here, the composer
  comes back with it, and `refute_has("#message-input")` is what notices.

  The other assertion worth its keep is that a *staff* member cannot reach this
  surface. Oversight is the owner's, not the team's; the whole point is that one
  staffer must not read another's private threads with a parent.
  """

  use KlassHeroWeb.FlowCase, async: false

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging

  setup do
    owner_user = user_fixture(%{intended_roles: [:provider]})

    provider =
      insert(:provider_profile_schema, identity_id: owner_user.id, business_name: "Bouldering Bees")

    staff_user = user_fixture(%{name: "Sam Staff", intended_roles: [:staff]})
    insert(:staff_member_schema, provider_id: provider.id, user_id: staff_user.id)

    parent_user = user_fixture(%{name: "Pat Parent", intended_roles: [:parent]})
    insert(:parent_profile_schema, identity_id: parent_user.id)

    staff_scope = staff_user |> Scope.for_user() |> Scope.resolve_roles()

    # Created by the staff member, exactly as the app would: the owner is seated
    # nowhere, which is the whole gap #746 closes.
    conversation =
      with_real_outbox(fn ->
        {:ok, conversation, _message} =
          Messaging.start_conversation_with_message(
            staff_scope,
            provider.id,
            parent_user.id,
            "Pickup will be five minutes late today"
          )

        conversation
      end)

    refute Messaging.participant?(conversation.id, owner_user.id)

    %{
      owner_user: owner_user,
      staff_user: staff_user,
      parent_user: parent_user,
      provider: provider,
      conversation: conversation
    }
  end

  describe "access" do
    test "a staff member cannot reach the staff-conversations index", %{staff_user: staff_user} do
      build_conn()
      |> log_in_user(staff_user)
      |> visit(~p"/provider/messages/staff")
      |> refute_has("#staff-conversations")
    end

    test "a parent cannot reach a thread through this surface", %{
      parent_user: parent_user,
      conversation: conversation
    } do
      build_conn()
      |> log_in_user(parent_user)
      |> visit(~p"/provider/messages/staff/#{conversation.id}")
      |> refute_has("[data-role=read-only-note]")
    end

    test "another provider's owner is bounced off a thread that is not theirs", %{
      conversation: conversation
    } do
      stranger = user_fixture(%{intended_roles: [:provider]})
      insert(:provider_profile_schema, identity_id: stranger.id, business_name: "Rival Rock")

      build_conn()
      |> log_in_user(stranger)
      |> visit(~p"/provider/messages/staff/#{conversation.id}")
      |> assert_path(~p"/provider/messages/staff")
    end
  end

  describe "the index" do
    test "lists the thread the staff member started, with their name attached", %{
      owner_user: owner_user
    } do
      build_conn()
      |> log_in_user(owner_user)
      |> visit(~p"/provider/messages/staff")
      |> assert_has("[data-role=conversation-card]")
      |> assert_has("[data-role=staff-attribution]", text: "Sam Staff")
      |> assert_has("[data-role=conversation-card]", text: "Pat Parent")
    end

    # The SAME parent the staff member already messaged, on purpose. This used to be
    # impossible: identity was keyed on provider + parent, so the owner was handed the
    # staff member's thread and `SendMessage` then refused them as `:not_participant`
    # (#1521). The principal pair keys on both parties, so each gets their own thread.
    test "the owner's own threads stay on their own tab", %{
      owner_user: owner_user,
      provider: provider,
      parent_user: parent_user,
      conversation: staff_thread
    } do
      owner_scope = owner_user |> Scope.for_user() |> Scope.resolve_roles()

      mine =
        with_real_outbox(fn ->
          {:ok, conversation, _} =
            Messaging.start_conversation_with_message(
              owner_scope,
              provider.id,
              parent_user.id,
              "Following up myself"
            )

          conversation
        end)

      assert mine.id != staff_thread.id
      assert Messaging.participant?(mine.id, owner_user.id)
      refute Messaging.participant?(staff_thread.id, owner_user.id)

      build_conn()
      |> log_in_user(owner_user)
      |> visit(~p"/provider/messages/staff")
      |> refute_has("#staff-conversations-#{mine.id}")
      |> assert_has("[data-role=conversation-card]")
    end

    test "both tabs are reachable from the inbox", %{owner_user: owner_user} do
      build_conn()
      |> log_in_user(owner_user)
      |> visit(~p"/provider/messages")
      |> assert_has("[data-role=provider-message-tabs]")
      |> click_link("Staff conversations")
      |> assert_path(~p"/provider/messages/staff")
    end
  end

  describe "the thread" do
    test "renders the messages the owner was never party to", %{
      owner_user: owner_user,
      conversation: conversation
    } do
      build_conn()
      |> log_in_user(owner_user)
      |> visit(~p"/provider/messages/staff/#{conversation.id}")
      |> assert_has("#conversation-thread")
      |> assert_has("[data-role=message]", text: "Pickup will be five minutes late today")
      |> assert_has("[data-role=read-only-note]")
    end

    test "offers no way to write into it", %{owner_user: owner_user, conversation: conversation} do
      build_conn()
      |> log_in_user(owner_user)
      |> visit(~p"/provider/messages/staff/#{conversation.id}")
      |> refute_has("#message-input")
      |> refute_has("[data-role=send-message-btn]")
      |> refute_has("textarea")
    end

    test "seats nobody and moves no read receipt", %{
      owner_user: owner_user,
      conversation: conversation
    } do
      before = Messaging.get_conversation_by_id(conversation.id, preload: [:participants])

      build_conn()
      |> log_in_user(owner_user)
      |> visit(~p"/provider/messages/staff/#{conversation.id}")
      |> assert_has("#conversation-thread")

      refute Messaging.participant?(conversation.id, owner_user.id)

      assert {:ok, %{participants: participants_before}} = before

      assert {:ok, %{participants: participants_after}} =
               Messaging.get_conversation_by_id(conversation.id, preload: [:participants])

      assert Enum.map(participants_before, & &1.last_read_at) ==
               Enum.map(participants_after, & &1.last_read_at)

      assert length(participants_after) == length(participants_before)
    end

    test "a malformed id lands back on the index", %{owner_user: owner_user} do
      build_conn()
      |> log_in_user(owner_user)
      |> visit(~p"/provider/messages/staff/not-a-uuid")
      |> assert_path(~p"/provider/messages/staff")
    end
  end
end
