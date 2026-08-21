defmodule KlassHeroWeb.Flows.MessagingComposeTest do
  @moduledoc """
  Flow test for #1446: opening compose must not create a `Conversation`.

  Runs under `with_real_outbox/1` so the send path goes all the way through the
  `ConversationSummaries` projection — the inbox reads that read table, so a
  test that stops at the write side would not see what the parent sees.
  """

  use KlassHeroWeb.FlowCase, async: false

  alias KlassHero.Messaging.Conversation
  alias KlassHero.Repo

  setup do
    provider_user = user_fixture(%{intended_roles: [:provider]})
    provider = insert(:provider_profile_schema, identity_id: provider_user.id)
    program = insert(:program_schema, provider_id: provider.id)

    parent_user = user_fixture(%{intended_roles: [:parent]})
    parent = insert(:parent_profile_schema, identity_id: parent_user.id)
    {child, _parent} = insert_child_with_guardian(parent: parent)

    insert(:enrollment_schema,
      program_id: program.id,
      child_id: child.id,
      parent_id: parent.id,
      status: "confirmed",
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )

    compose_path =
      "/provider/messages/new?provider_id=#{provider.id}&user_id=#{parent_user.id}&program_id=#{program.id}"

    %{
      provider_user: provider_user,
      parent_user: parent_user,
      compose_path: compose_path
    }
  end

  test "opening compose and leaving creates nothing", %{
    conn: conn,
    provider_user: provider_user,
    parent_user: parent_user,
    compose_path: compose_path
  } do
    conn
    |> log_in_user(provider_user)
    |> visit(compose_path)
    |> assert_has("h1", text: parent_user.name)
    |> assert_has("a[href='/provider/messages']")
    |> refute_has("[data-role=message]")
    |> assert_has("#message-input")
    |> visit(~p"/provider/messages")

    assert Repo.aggregate(Conversation, :count, :id) == 0

    build_conn()
    |> log_in_user(parent_user)
    |> visit(~p"/messages")
    |> assert_has("#conversations-empty-state")
  end

  test "sending the first message creates the thread and it reaches the parent", %{
    conn: conn,
    provider_user: provider_user,
    parent_user: parent_user,
    compose_path: compose_path
  } do
    with_real_outbox(fn ->
      conn
      |> log_in_user(provider_user)
      |> visit(compose_path)
      |> fill_in("#message-input", "Message", with: "Welcome aboard!")
      |> submit()
    end)

    assert Repo.aggregate(Conversation, :count, :id) == 1

    build_conn()
    |> log_in_user(parent_user)
    |> visit(~p"/messages")
    |> refute_has("#conversations-empty-state")
    |> click_link("Welcome aboard!")
    |> assert_has("[data-role=message]", text: "Welcome aboard!")
  end
end
