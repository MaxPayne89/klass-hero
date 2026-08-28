defmodule KlassHeroWeb.Staff.MessagesLive.StaffInboxVisibilityTest do
  @moduledoc """
  Regression tests for #817: staff members added to conversations must
  appear in `/staff/messages` without a server restart. Exercises
  `CreateDirectConversation` → `AddAssignedStaff` → participant rows →
  `ListStaffConversations` → LiveView render.

  "Without a server restart" was the whole difficulty while the inbox read
  `conversation_summaries`: this file started that projection per test and replayed
  staged events into it by hand, because a row could only appear once the projection
  had written one. Reading the write model live (ADR-0023) deletes the question —
  the participant row *is* the fact the inbox renders.
  """

  use KlassHeroWeb.ConnCase, async: false

  import KlassHero.AccountsFixtures
  import KlassHero.EventTestHelper
  import KlassHero.Factory, only: [insert: 2]
  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.StaffAssignmentHandler
  alias KlassHero.Messaging.StartConversationWithMessage
  alias KlassHero.Provider
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.StaffMember

  setup do
    setup_test_integration_events()
    :ok
  end

  # Retires the real assignment row *before* delivering the event, and builds the
  # event through the producer's own constructor.
  #
  # Both mattered as of #784. Entitlement to a program's conversations is now the
  # union of the program roster and any session override, and the handler re-reads
  # it before evicting anyone — so an event fired over a row that still stands is
  # correctly ignored. The hand-rolled payloads this replaced also carried an
  # `unassigned_at`/`assigned_at` that `Provider.Events` deliberately omits, which is
  # the payload drift #1309 was about.
  defp unassign_and_deliver(provider, program, assignment, staff_user) do
    {:ok, retired} =
      Provider.unassign_staff_from_program(program.id, assignment.staff_member_id, provider.id)

    StaffAssignmentHandler.handle_event(
      Provider.Events.staff_unassigned_from_program(retired, %StaffMember{user_id: staff_user.id})
    )
  end

  describe "staff inbox visibility" do
    test "staff sees a direct conversation created in a program they were assigned to before creation",
         %{conn: conn} do
      provider_owner = user_fixture()
      provider = provider_profile_fixture(%{identity_id: provider_owner.id})
      program = insert(:program_schema, provider_id: provider.id)
      parent = user_fixture()

      staff_user = user_fixture(intended_roles: [:staff])

      staff_member_fixture(%{
        provider_id: provider.id,
        user_id: staff_user.id,
        active: true,
        invitation_status: :accepted
      })

      assign_active_staff(%{
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
          business_name: "Test Provider"
        }
      }

      assert {:ok, conversation, _message} =
               StartConversationWithMessage.execute(scope, provider.id, parent.id, "Hello", program_id: program.id)

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
          business_name: "Test Provider"
        }
      }

      assert {:ok, conversation, _message} =
               StartConversationWithMessage.execute(scope, provider.id, parent.id, "Hello", program_id: program.id)

      # Now assign staff via the integration event the Provider context would send
      staff_user = user_fixture(intended_roles: [:staff])

      staff_member_fixture(%{
        provider_id: provider.id,
        user_id: staff_user.id,
        active: true,
        invitation_status: :accepted
      })

      assignment =
        assign_active_staff(%{
          provider_id: provider.id,
          program_id: program.id,
          staff_user_id: staff_user.id
        })

      assert :ok =
               StaffAssignmentHandler.handle_event(
                 Provider.Events.staff_assigned_to_program(assignment, %StaffMember{user_id: staff_user.id})
               )

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

      staff_user = user_fixture(intended_roles: [:staff])

      staff_member_fixture(%{
        provider_id: provider.id,
        user_id: staff_user.id,
        active: true,
        invitation_status: :accepted
      })

      assignment =
        assign_active_staff(%{
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
          business_name: "Test Provider"
        }
      }

      assert {:ok, conversation, _message} =
               StartConversationWithMessage.execute(scope, provider.id, parent.id, "Hello", program_id: program.id)

      assert :ok = unassign_and_deliver(provider, program, assignment, staff_user)

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

      staff_user = user_fixture(intended_roles: [:staff])

      staff_member_fixture(%{
        provider_id: provider.id,
        user_id: staff_user.id,
        active: true,
        invitation_status: :accepted
      })

      assignment =
        assign_active_staff(%{
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
          business_name: "Test Provider"
        }
      }

      # ACT 1 — create conversation; staff is included from the start
      assert {:ok, conversation, _message} =
               StartConversationWithMessage.execute(scope, provider.id, parent.id, "Hello", program_id: program.id)

      staff_conn = log_in_user(conn, staff_user)
      {:ok, view, _html} = live(staff_conn, ~p"/staff/messages")

      assert has_element?(view, "#conversations a[href*='#{conversation.id}']"),
             "ACT 1: staff should see the conversation after initial create"

      # ACT 2 — unassign staff; conversation disappears from inbox
      assert :ok = unassign_and_deliver(provider, program, assignment, staff_user)

      {:ok, view, _html} = live(log_in_user(conn, staff_user), ~p"/staff/messages")

      refute has_element?(view, "#conversations a[href*='#{conversation.id}']"),
             "ACT 2: staff should NOT see the conversation after unassignment"

      # ACT 3 — re-assign the SAME staff; conversation must re-appear
      reassignment =
        assign_active_staff(%{
          provider_id: provider.id,
          program_id: program.id,
          staff_user_id: staff_user.id
        })

      assert :ok =
               StaffAssignmentHandler.handle_event(
                 Provider.Events.staff_assigned_to_program(reassignment, %StaffMember{user_id: staff_user.id})
               )

      {:ok, view, _html} = live(log_in_user(conn, staff_user), ~p"/staff/messages")

      assert has_element?(view, "#conversations a[href*='#{conversation.id}']"),
             "ACT 3: previously-unassigned staff should see the conversation again after re-assignment"
    end
  end
end
