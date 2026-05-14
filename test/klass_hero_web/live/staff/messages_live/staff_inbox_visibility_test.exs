defmodule KlassHeroWeb.Staff.MessagesLive.StaffInboxVisibilityTest do
  @moduledoc """
  Regression tests for #817: staff members added to conversations must
  appear in `/staff/messages` without a server restart. Exercises the full
  `CreateDirectConversation` → `AddAssignedStaff` → `:participant_added`
  event flow → `ConversationSummaries` projection → `ListConversations`
  query → LiveView render.

  Uses `async: false` so the shared Ecto sandbox lets the supervised
  projection process see the test's DB writes.
  """

  use KlassHeroWeb.ConnCase, async: false

  import KlassHero.AccountsFixtures
  import KlassHero.EventTestHelper
  import KlassHero.Factory, only: [insert: 2]
  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ProgramStaffParticipantRepository
  alias KlassHero.Messaging.Adapters.Driven.Projections.ConversationSummaries
  alias KlassHero.Messaging.Adapters.Driving.Events.StaffAssignmentHandler
  alias KlassHero.Messaging.Application.Commands.CreateDirectConversation
  alias KlassHero.Provider.Domain.Models.ProviderProfile
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @projection_name :inbox_e2e_projection

  setup do
    # Projections are not started in the test supervision tree by default
    # (see config/test.exs `start_projections: false`). Start one per test
    # so the event flow has a live consumer.
    pid = start_supervised!({ConversationSummaries, name: @projection_name})
    _ = :sys.get_state(@projection_name)

    # In test env the integration-event publisher captures to process state
    # (see TestIntegrationEventPublisher). For an end-to-end inbox flow we
    # must replay those captured events to the PubSub topic the projection
    # is subscribed to.
    setup_test_integration_events()

    {:ok, projection: pid}
  end

  defp flush_to_projection do
    get_published_integration_events()
    |> Enum.each(fn event ->
      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:#{event.event_type}",
        {:integration_event, event}
      )
    end)

    clear_integration_events()
    _ = :sys.get_state(@projection_name)
    :ok
  end

  describe "staff inbox visibility" do
    test "staff sees a direct conversation created in a program they were assigned to before creation",
         %{conn: conn} do
      provider_owner = user_fixture()
      provider = provider_profile_fixture(%{identity_id: provider_owner.id})
      program = insert(:program_schema, provider_id: provider.id)
      parent = user_fixture()

      staff_user = user_fixture(intended_roles: [:staff_provider])

      staff_member_fixture(%{
        provider_id: provider.id,
        user_id: staff_user.id,
        active: true,
        invitation_status: :accepted
      })

      ProgramStaffParticipantRepository.upsert_active(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff_user.id
      })

      scope = %Scope{
        user: provider_owner,
        roles: [:provider],
        parent: nil,
        provider: %ProviderProfile{
          id: provider.id,
          identity_id: provider_owner.id,
          business_name: "Test Provider",
          subscription_tier: :professional
        }
      }

      assert {:ok, conversation} =
               CreateDirectConversation.execute(scope, provider.id, parent.id, program_id: program.id)

      flush_to_projection()

      staff_conn = log_in_user(conn, staff_user)
      {:ok, view, _html} = live(staff_conn, ~p"/staff/messages")

      assert has_element?(view, "#conversations")

      assert has_element?(view, "#conversations a[href*='#{conversation.id}']"),
             "expected the newly-created conversation #{conversation.id} to appear in /staff/messages"

      refute has_element?(view, "#conversations-empty-state")
    end

    test "staff sees a conversation they were added to after the fact (program staff assignment)",
         %{conn: conn} do
      provider_owner = user_fixture()
      provider = provider_profile_fixture(%{identity_id: provider_owner.id})
      program = insert(:program_schema, provider_id: provider.id)
      parent = user_fixture()

      # Conversation exists BEFORE staff is assigned to the program
      scope = %Scope{
        user: provider_owner,
        roles: [:provider],
        parent: nil,
        provider: %ProviderProfile{
          id: provider.id,
          identity_id: provider_owner.id,
          business_name: "Test Provider",
          subscription_tier: :professional
        }
      }

      assert {:ok, conversation} =
               CreateDirectConversation.execute(scope, provider.id, parent.id, program_id: program.id)

      flush_to_projection()

      # Now assign staff via the integration event the Provider context would send
      staff_user = user_fixture(intended_roles: [:staff_provider])

      staff_member_fixture(%{
        provider_id: provider.id,
        user_id: staff_user.id,
        active: true,
        invitation_status: :accepted
      })

      assignment_event = %IntegrationEvent{
        event_id: Ecto.UUID.generate(),
        event_type: :staff_assigned_to_program,
        source_context: :provider,
        entity_type: :staff_member,
        entity_id: Ecto.UUID.generate(),
        occurred_at: DateTime.utc_now(),
        payload: %{
          provider_id: provider.id,
          program_id: program.id,
          staff_member_id: Ecto.UUID.generate(),
          staff_user_id: staff_user.id,
          assigned_at: DateTime.utc_now()
        }
      }

      assert :ok = StaffAssignmentHandler.handle_event(assignment_event)

      flush_to_projection()

      staff_conn = log_in_user(conn, staff_user)
      {:ok, view, _html} = live(staff_conn, ~p"/staff/messages")

      assert has_element?(view, "#conversations a[href*='#{conversation.id}']"),
             "expected the back-filled conversation to appear in /staff/messages without a server restart"
    end

    test "staff stops seeing a conversation after being unassigned from its program",
         %{conn: conn} do
      provider_owner = user_fixture()
      provider = provider_profile_fixture(%{identity_id: provider_owner.id})
      program = insert(:program_schema, provider_id: provider.id)
      parent = user_fixture()

      staff_user = user_fixture(intended_roles: [:staff_provider])

      staff_member_fixture(%{
        provider_id: provider.id,
        user_id: staff_user.id,
        active: true,
        invitation_status: :accepted
      })

      ProgramStaffParticipantRepository.upsert_active(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff_user.id
      })

      scope = %Scope{
        user: provider_owner,
        roles: [:provider],
        parent: nil,
        provider: %ProviderProfile{
          id: provider.id,
          identity_id: provider_owner.id,
          business_name: "Test Provider",
          subscription_tier: :professional
        }
      }

      assert {:ok, conversation} =
               CreateDirectConversation.execute(scope, provider.id, parent.id, program_id: program.id)

      flush_to_projection()

      # Now unassign the staff
      unassignment_event = %IntegrationEvent{
        event_id: Ecto.UUID.generate(),
        event_type: :staff_unassigned_from_program,
        source_context: :provider,
        entity_type: :staff_member,
        entity_id: Ecto.UUID.generate(),
        occurred_at: DateTime.utc_now(),
        payload: %{
          provider_id: provider.id,
          program_id: program.id,
          staff_member_id: Ecto.UUID.generate(),
          staff_user_id: staff_user.id,
          unassigned_at: DateTime.utc_now()
        }
      }

      assert :ok = StaffAssignmentHandler.handle_event(unassignment_event)

      flush_to_projection()

      staff_conn = log_in_user(conn, staff_user)
      {:ok, view, _html} = live(staff_conn, ~p"/staff/messages")

      refute has_element?(view, "#conversations a[href*='#{conversation.id}']"),
             "expected the conversation to disappear from the unassigned staff's inbox"
    end

    test "full cycle: assign → unassign → re-assign — inbox visibility tracks each step",
         %{conn: conn} do
      provider_owner = user_fixture()
      provider = provider_profile_fixture(%{identity_id: provider_owner.id})
      program = insert(:program_schema, provider_id: provider.id)
      parent = user_fixture()

      staff_user = user_fixture(intended_roles: [:staff_provider])

      staff_member_fixture(%{
        provider_id: provider.id,
        user_id: staff_user.id,
        active: true,
        invitation_status: :accepted
      })

      ProgramStaffParticipantRepository.upsert_active(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff_user.id
      })

      scope = %Scope{
        user: provider_owner,
        roles: [:provider],
        parent: nil,
        provider: %ProviderProfile{
          id: provider.id,
          identity_id: provider_owner.id,
          business_name: "Test Provider",
          subscription_tier: :professional
        }
      }

      # ACT 1 — create conversation; staff is included from the start
      assert {:ok, conversation} =
               CreateDirectConversation.execute(scope, provider.id, parent.id, program_id: program.id)

      flush_to_projection()

      staff_conn = log_in_user(conn, staff_user)
      {:ok, view, _html} = live(staff_conn, ~p"/staff/messages")

      assert has_element?(view, "#conversations a[href*='#{conversation.id}']"),
             "ACT 1: staff should see the conversation after initial create"

      # ACT 2 — unassign staff; conversation disappears from inbox
      unassignment_event = %IntegrationEvent{
        event_id: Ecto.UUID.generate(),
        event_type: :staff_unassigned_from_program,
        source_context: :provider,
        entity_type: :staff_member,
        entity_id: Ecto.UUID.generate(),
        occurred_at: DateTime.utc_now(),
        payload: %{
          provider_id: provider.id,
          program_id: program.id,
          staff_member_id: Ecto.UUID.generate(),
          staff_user_id: staff_user.id,
          unassigned_at: DateTime.utc_now()
        }
      }

      assert :ok = StaffAssignmentHandler.handle_event(unassignment_event)
      flush_to_projection()

      {:ok, view, _html} = live(log_in_user(conn, staff_user), ~p"/staff/messages")

      refute has_element?(view, "#conversations a[href*='#{conversation.id}']"),
             "ACT 2: staff should NOT see the conversation after unassignment"

      # ACT 3 — re-assign the SAME staff; conversation must re-appear
      reassignment_event = %IntegrationEvent{
        event_id: Ecto.UUID.generate(),
        event_type: :staff_assigned_to_program,
        source_context: :provider,
        entity_type: :staff_member,
        entity_id: Ecto.UUID.generate(),
        occurred_at: DateTime.utc_now(),
        payload: %{
          provider_id: provider.id,
          program_id: program.id,
          staff_member_id: Ecto.UUID.generate(),
          staff_user_id: staff_user.id,
          assigned_at: DateTime.utc_now()
        }
      }

      assert :ok = StaffAssignmentHandler.handle_event(reassignment_event)
      flush_to_projection()

      {:ok, view, _html} = live(log_in_user(conn, staff_user), ~p"/staff/messages")

      assert has_element?(view, "#conversations a[href*='#{conversation.id}']"),
             "ACT 3: previously-unassigned staff should see the conversation again after re-assignment"
    end
  end
end
