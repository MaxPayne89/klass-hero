defmodule KlassHeroWeb.E2E.Messaging.BroadcastTest do
  @moduledoc """
  E2E tests for broadcast messaging flows.

  Scenario 1: Provider broadcasts a message and parent sees it in their conversation list.
  Scenario 2: Parent replies privately to a broadcast and provider sees the private conversation.
  """

  use KlassHeroWeb.E2ECase

  alias KlassHero.Messaging.Adapters.Driven.Projections.ConversationSummaries

  describe "broadcast messaging" do
    setup %{sandbox_metadata: metadata} do
      # ConversationSummaries is disabled in test config (start_projections: false)
      # because it bootstraps outside the sandbox. In E2E tests with shared sandbox,
      # we start it after the sandbox is established so it can see test data.
      start_supervised!(ConversationSummaries)

      provider_user = user_fixture(%{intended_roles: [:provider]}) |> set_password()

      provider =
        insert(:provider_profile_schema,
          identity_id: provider_user.id,
          subscription_tier: "professional"
        )

      parent_user = user_fixture(%{intended_roles: [:parent]}) |> set_password()

      parent =
        insert(:parent_profile_schema,
          identity_id: parent_user.id,
          subscription_tier: "active"
        )

      {child, _parent_schema} = insert_child_with_guardian(parent: parent)
      program = insert(:program_schema, provider_id: provider.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        child_id: child.id,
        status: "confirmed"
      )

      provider_session = new_session(metadata) |> log_in(provider_user)
      parent_session = new_session(metadata) |> log_in(parent_user)

      %{
        provider_session: provider_session,
        parent_session: parent_session,
        program: program
      }
    end

    test "provider broadcasts message and parent sees it", %{
      provider_session: provider_session,
      parent_session: parent_session,
      program: program
    } do
      provider_session
      |> visit("/provider/programs/#{program.id}/broadcast")
      |> fill_in(Query.css("#content"), with: "Field trip tomorrow at 9am!")
      |> click(Query.button("Send Broadcast"))

      assert_has(
        provider_session,
        Query.css("[data-role=message]", text: "Field trip tomorrow at 9am!")
      )

      # Test event publishers don't use PubSub, so the ConversationSummaries
      # projection never receives the integration event in E2E — rebuild manually.
      rebuild_summaries()

      parent_session
      |> visit_conversations(:parent)
      |> assert_has(Query.css("[data-role=conversation-card]", text: "Field trip tomorrow at 9am!"))
    end

    test "parent replies privately to broadcast and provider sees private conversation", %{
      provider_session: provider_session,
      parent_session: parent_session,
      program: program
    } do
      provider_session
      |> visit("/provider/programs/#{program.id}/broadcast")
      |> fill_in(Query.css("#content"), with: "Reminder: bring sunscreen")
      |> click(Query.button("Send Broadcast"))

      assert_has(
        provider_session,
        Query.css("[data-role=message]", text: "Reminder: bring sunscreen")
      )

      # Test event publishers don't use PubSub, so the ConversationSummaries
      # projection never receives the integration event in E2E — rebuild manually.
      rebuild_summaries()

      parent_session
      |> visit_conversations(:parent)
      |> open_conversation("Reminder: bring sunscreen")

      parent_session |> click(Query.button("Reply privately"))
      parent_session |> send_message("Should we also bring lunch?")

      wait_and_rebuild_summaries()

      provider_session
      |> visit_conversations(:provider)
      |> assert_has(Query.css("[data-role=conversation-card]", text: "Should we also bring lunch?"))
    end
  end
end
