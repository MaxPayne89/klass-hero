defmodule KlassHeroWeb.Flows.MessagingDirectMessageTest do
  @moduledoc """
  Flow test for a direct conversation between a provider and a parent.

  Migrated from `test/e2e/messaging/direct_message_test.exs`. The browser bought
  nothing here — both tests navigated to re-read the page rather than asserting a
  live push — while costing the projection fidelity the tier was supposed to have:
  `ConversationSummaries` had to be hand-started and hand-rebuilt because no event
  was ever delivered. Under `with_real_outbox/1` the projection runs as
  `{ConversationSummaries, :project}`, the way production runs it.
  """

  use KlassHeroWeb.FlowCase, async: false

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging
  alias KlassHero.Provider.ProviderProfile

  setup do
    provider_user = user_fixture(%{intended_roles: [:provider]})
    provider = insert(:provider_profile_schema, identity_id: provider_user.id)

    parent_user = user_fixture(%{intended_roles: [:parent]})
    insert(:parent_profile_schema, identity_id: parent_user.id)

    provider_scope = provider_user |> Scope.for_user() |> Scope.resolve_roles()

    conversation =
      with_real_outbox(fn ->
        {:ok, conversation} =
          Messaging.create_direct_conversation(provider_scope, provider.id, parent_user.id)

        {:ok, _} =
          Messaging.send_message(conversation.id, provider_user.id, "Hello! Welcome to the program.")

        conversation
      end)

    %{provider_user: provider_user, parent_user: parent_user, conversation: conversation}
  end

  test "a provider's message reaches the parent's thread", %{
    conn: conn,
    provider_user: provider_user,
    parent_user: parent_user,
    conversation: conversation
  } do
    with_real_outbox(fn ->
      conn
      |> log_in_user(provider_user)
      |> visit(~p"/provider/messages/#{conversation.id}")
      |> assert_has("[data-role=message]", text: "Hello! Welcome to the program.")
      |> fill_in("#message-input", "Message", with: "Don't forget your homework!")
      # submit/1 rather than click_button/3: the send control is icon-only, and
      # click_button matches rendered text, not the aria-label.
      |> submit()
    end)

    build_conn()
    |> log_in_user(parent_user)
    |> visit(~p"/messages/#{conversation.id}")
    |> assert_has("[data-role=message]", text: "Don't forget your homework!")
  end

  test "a parent's reply reaches the provider's thread", %{
    conn: conn,
    provider_user: provider_user,
    parent_user: parent_user,
    conversation: conversation
  } do
    with_real_outbox(fn ->
      conn
      |> log_in_user(parent_user)
      |> visit(~p"/messages/#{conversation.id}")
      |> assert_has("[data-role=message]", text: "Hello! Welcome to the program.")
      |> fill_in("#message-input", "Message", with: "Thanks! What time should we arrive?")
      # submit/1 rather than click_button/3: the send control is icon-only, and
      # click_button matches rendered text, not the aria-label.
      |> submit()
    end)

    build_conn()
    |> log_in_user(provider_user)
    |> visit(~p"/provider/messages/#{conversation.id}")
    |> assert_has("[data-role=message]", text: "Thanks! What time should we arrive?")
  end

  # #745 — the disclosure half of admin monitoring (#744). Both sides must see it:
  # the notice is what makes platform-staff read access something participants were
  # told about rather than something done to them.
  test "both sides see the monitoring notice", %{
    provider_user: provider_user,
    parent_user: parent_user,
    conversation: conversation
  } do
    build_conn()
    |> log_in_user(parent_user)
    |> visit(~p"/messages/#{conversation.id}")
    |> assert_has("[data-role=monitoring-notice]", text: "Klass Hero staff")

    build_conn()
    |> log_in_user(provider_user)
    |> visit(~p"/provider/messages/#{conversation.id}")
    |> assert_has("[data-role=monitoring-notice]", text: "Klass Hero staff")
  end

  # "Klass Hero staff" appears in BOTH wordings, so the assertion above cannot tell
  # them apart. The provider-reviewed clause is what distinguishes a thread with a
  # parent in it, and it is what must NOT appear on an internal one below.
  test "a thread with a parent names the provider as a possible reader", %{
    parent_user: parent_user,
    conversation: conversation
  } do
    build_conn()
    |> log_in_user(parent_user)
    |> visit(~p"/messages/#{conversation.id}")
    |> assert_has("[data-role=monitoring-notice]", text: "activity provider")
  end

  # #747 made the provider a *principal* rather than a third-party overseer. The
  # default wording would tell an owner that "the activity provider" — themselves —
  # may review their own message, and invoke child safeguarding over a thread with
  # neither child nor parent in it.
  test "an owner<->staff thread drops the provider-review and child-safety clauses", %{
    provider_user: provider_user
  } do
    provider = KlassHero.Repo.get_by!(ProviderProfile, identity_id: provider_user.id)

    staff_user = user_fixture(%{intended_roles: [:staff]})
    insert(:staff_member_schema, provider_id: provider.id, user_id: staff_user.id, active: true)

    provider_scope = provider_user |> Scope.for_user() |> Scope.resolve_roles()

    conversation =
      with_real_outbox(fn ->
        {:ok, conversation} =
          Messaging.create_direct_conversation(provider_scope, provider.id, staff_user.id)

        {:ok, _} = Messaging.send_message(conversation.id, provider_user.id, "Rota for next week.")

        conversation
      end)

    for {user, path} <- [
          {provider_user, ~p"/provider/messages/#{conversation.id}"},
          {staff_user, ~p"/staff/messages/#{conversation.id}"}
        ] do
      build_conn()
      |> log_in_user(user)
      |> visit(path)
      |> assert_has("[data-role=monitoring-notice]", text: "Klass Hero staff")
      |> refute_has("[data-role=monitoring-notice]", text: "activity provider")
      |> refute_has("[data-role=monitoring-notice]", text: "keep children safe")
    end
  end
end
