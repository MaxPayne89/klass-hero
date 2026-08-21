defmodule KlassHeroWeb.E2E.JsHooksTest do
  @moduledoc """
  The JavaScript hooks in `assets/js/hooks/`, which no server-side test can see.

  `AutoResizeTextarea` is the one with a server contract: after a successful send
  the LiveView pushes a `clear_message_input` event, and the hook empties the
  textarea and resizes it. LiveView's morphdom deliberately skips patching form
  inputs after `phx-submit`, so without the hook the composer keeps the text the
  parent just sent — visible only in a browser.
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

    %{
      session: new_session(metadata) |> log_in(provider_user),
      conversation: conversation
    }
  end

  test "AutoResizeTextarea clears the composer after a send", %{
    session: session,
    conversation: conversation
  } do
    session
    |> visit("/provider/messages/#{conversation.id}")
    |> fill_in(Query.css("#message-input"), with: "See you Thursday")
    |> click(Query.css("[data-role=send-message-btn]"))
    |> assert_has(Query.css("[data-role=message]", text: "See you Thursday"))

    # The hook's job: without it the textarea still holds the sent text, because
    # LiveView does not patch a submitted form's inputs.
    session
    |> await(fn s -> composer_value(s) == "" end,
      message: "the composer still held the sent message"
    )
  end

  defp composer_value(session) do
    session
    |> find(Query.css("#message-input"))
    |> Wallaby.Element.value()
  end
end
