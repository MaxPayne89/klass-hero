defmodule KlassHeroWeb.E2E.LivePushTest do
  @moduledoc """
  Two people in the same conversation at the same time.

  This is the property the browser tier exists for and the one the old messaging
  e2e tests never asserted: every one of them navigated and re-read the page, which
  proves persistence, not push. Here the parent never reloads — the message has to
  arrive over the socket, driven by `Notifications.message_sent/2`, and be patched
  into a DOM that is already on screen.

  `phoenix_test` cannot express this: a session is one conn pipeline, with no way
  to hold a second page open while the first acts.
  """

  use KlassHeroWeb.E2ECase

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging

  setup %{sandbox_metadata: metadata} do
    provider_user = user_fixture(%{intended_roles: [:provider]}) |> set_password()
    provider = insert(:provider_profile_schema, identity_id: provider_user.id)

    parent_user = user_fixture(%{intended_roles: [:parent]}) |> set_password()
    insert(:parent_profile_schema, identity_id: parent_user.id)

    provider_scope = provider_user |> Scope.for_user() |> Scope.resolve_roles()

    {:ok, conversation} =
      Messaging.create_direct_conversation(provider_scope, provider.id, parent_user.id)

    {:ok, _} = Messaging.send_message(conversation.id, provider_user.id, "Welcome!")

    %{
      provider_session: new_session(metadata) |> log_in(provider_user),
      parent_session: new_session(metadata) |> log_in(parent_user),
      conversation: conversation
    }
  end

  test "a message appears in an open thread without the reader navigating", %{
    provider_session: provider_session,
    parent_session: parent_session,
    conversation: conversation
  } do
    # The parent is sitting in the thread and will not touch the page again.
    parent_session
    |> visit("/messages/#{conversation.id}")
    |> assert_has(Query.css("[data-role=message]", text: "Welcome!"))

    provider_session
    |> visit("/provider/messages/#{conversation.id}")
    |> fill_in(Query.css("#message-input"), with: "Practice is cancelled today")
    |> click(Query.css("[data-role=send-message-btn]"))

    assert_has(
      parent_session,
      Query.css("[data-role=message]", text: "Practice is cancelled today")
    )
  end
end
