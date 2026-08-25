defmodule KlassHeroWeb.Flows.MessagingBroadcastTest do
  @moduledoc """
  Flow tests for program broadcasts and the private replies they invite.

  Migrated from `test/e2e/messaging/broadcast_test.exs`. Both hops now travel the
  real delivery path: `conversation_created` and `message_sent` reach
  `{ConversationSummaries, :project}`, so the parent's list is a projected read
  rather than a rebuilt one.
  """

  use KlassHeroWeb.FlowCase, async: false

  setup do
    provider_user = user_fixture(%{intended_roles: [:provider]})
    provider = insert(:provider_profile_schema, identity_id: provider_user.id)

    parent_user = user_fixture(%{intended_roles: [:parent]})
    parent = insert(:parent_profile_schema, identity_id: parent_user.id)

    {child, _parent} = insert_child_with_guardian(parent: parent)
    program = insert(:program_schema, provider_id: provider.id)

    insert(:enrollment_schema,
      program_id: program.id,
      parent_id: parent.id,
      child_id: child.id,
      status: "confirmed"
    )

    %{provider_user: provider_user, parent_user: parent_user, program: program}
  end

  test "a broadcast reaches the enrolled parent's conversation list", %{
    conn: conn,
    provider_user: provider_user,
    parent_user: parent_user,
    program: program
  } do
    with_real_outbox(fn ->
      conn
      |> log_in_user(provider_user)
      |> visit(~p"/provider/programs/#{program.id}/broadcast")
      |> fill_in("#content", "Message", with: "Field trip tomorrow at 9am!", exact: false)
      |> click_button("Send Broadcast")
      |> assert_has("[data-role=message]", text: "Field trip tomorrow at 9am!")
    end)

    build_conn()
    |> log_in_user(parent_user)
    |> visit(~p"/messages")
    |> assert_has("[data-role=conversation-card]", text: "Field trip tomorrow at 9am!")
  end

  # #381: membership used to be a send-time snapshot, so a family who enrolled between
  # two broadcasts was not a participant and the thread was invisible to them. The
  # badge assertion is the other half of the requirement — the history is readable,
  # but arriving late must not arrive as a pile of notifications.
  test "a parent who enrolls after the broadcast sees its history, unbadged", %{
    conn: conn,
    provider_user: provider_user,
    program: program
  } do
    with_real_outbox(fn ->
      conn
      |> log_in_user(provider_user)
      |> visit(~p"/provider/programs/#{program.id}/broadcast")
      |> fill_in("#content", "Message", with: "Swimming kit needed on Friday", exact: false)
      |> click_button("Send Broadcast")
      |> assert_has("[data-role=message]", text: "Swimming kit needed on Friday")
    end)

    late_user = user_fixture(%{intended_roles: [:parent]})
    late_parent = insert(:parent_profile_schema, identity_id: late_user.id)
    {late_child, _} = insert_child_with_guardian(parent: late_parent)

    with_real_outbox(fn ->
      {:ok, _enrollment} =
        KlassHero.Enrollment.create_enrollment(%{
          program_id: program.id,
          child_id: late_child.id,
          parent_id: late_parent.id,
          status: :confirmed,
          payment_method: "transfer",
          waivers: :deferred
        })
    end)

    build_conn()
    |> log_in_user(late_user)
    |> visit(~p"/messages")
    |> assert_has("[data-role=conversation-card]", text: "Swimming kit needed on Friday")
    |> refute_has("[data-role=unread-count]")

    # Pins the refute above: the badge is absent because the pre-join broadcast is
    # already read, not because this card never renders one.
    with_real_outbox(fn ->
      build_conn()
      |> log_in_user(provider_user)
      |> visit(~p"/provider/programs/#{program.id}/broadcast")
      |> fill_in("#content", "Message", with: "Bus leaves at 8am sharp", exact: false)
      |> click_button("Send Broadcast")
    end)

    build_conn()
    |> log_in_user(late_user)
    |> visit(~p"/messages")
    |> assert_has("[data-role=unread-count]", text: "1")
  end

  test "a parent's private reply to a broadcast reaches the provider's inbox", %{
    conn: conn,
    provider_user: provider_user,
    parent_user: parent_user,
    program: program
  } do
    with_real_outbox(fn ->
      conn
      |> log_in_user(provider_user)
      |> visit(~p"/provider/programs/#{program.id}/broadcast")
      |> fill_in("#content", "Message", with: "Reminder: bring sunscreen", exact: false)
      |> click_button("Send Broadcast")
      |> assert_has("[data-role=message]", text: "Reminder: bring sunscreen")
    end)

    with_real_outbox(fn ->
      build_conn()
      |> log_in_user(parent_user)
      |> visit(~p"/messages")
      |> click_link("[data-role=conversation-card]", "Reminder: bring sunscreen")
      |> click_button("Reply privately")
      |> fill_in("#message-input", "Message", with: "Should we also bring lunch?")
      |> submit()
    end)

    build_conn()
    |> log_in_user(provider_user)
    |> visit(~p"/provider/messages")
    |> assert_has("[data-role=conversation-card]", text: "Should we also bring lunch?")
  end
end
