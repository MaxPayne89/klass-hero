defmodule KlassHero.Messaging.StaffMessagingIntegrationTest do
  @moduledoc """
  End-to-end integration test for the staff messaging feature.
  Verifies the full flow: assign staff → staff added to conversations →
  staff can send messages → unassign doesn't remove from existing threads.

  Note: In the test environment the DomainEventBus uses TestEventPublisher, which
  collects events without routing them to handlers. This test drives the
  StaffAssignmentHandler directly to simulate what happens in production when
  the integration event bus delivers the event.
  """
  use KlassHero.DataCase, async: false

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.Accounts.User
  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ParticipantRepository
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ProgramStaffParticipantRepository
  alias KlassHero.Messaging.Adapters.Driving.Events.StaffAssignmentHandler
  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.Models.ProviderProfile
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  describe "staff messaging end-to-end" do
    setup do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      # The factory creates a real user for the provider via identity_id
      provider_user = KlassHero.Repo.get!(User, provider.identity_id)
      staff_user = AccountsFixtures.user_fixture()
      parent_user = AccountsFixtures.user_fixture()
      staff = insert(:staff_member_schema, provider_id: provider.id, user_id: staff_user.id)

      %{
        provider: provider,
        program: program,
        provider_user: provider_user,
        staff_user: staff_user,
        parent_user: parent_user,
        staff: staff
      }
    end

    test "full flow: assign → participate → send → unassign", ctx do
      # 1. Assign staff to program
      assert {:ok, assignment} =
               Provider.assign_staff_to_program(%{
                 provider_id: ctx.provider.id,
                 program_id: ctx.program.id,
                 staff_member_id: ctx.staff.id
               })

      # In the test environment, the DomainEventBus uses TestEventPublisher which
      # only collects events without routing them to handlers. We invoke the handler
      # directly, matching the integration event payload that would be published in prod.
      assert :ok =
               StaffAssignmentHandler.handle_event(
                 build_assignment_event(
                   ctx.provider.id,
                   ctx.program.id,
                   assignment.staff_member_id,
                   ctx.staff_user.id
                 )
               )

      # 2. Verify projection was populated
      staff_ids = ProgramStaffParticipantRepository.get_active_staff_user_ids(ctx.program.id)
      assert ctx.staff_user.id in staff_ids

      # 3. Create a conversation — staff should be auto-added (new conversations
      #    pick up staff from the projection during CreateDirectConversation)
      scope = build_provider_scope(ctx.provider, ctx.provider_user)

      {:ok, conversation} =
        Messaging.create_direct_conversation(scope, ctx.provider.id, ctx.parent_user.id, program_id: ctx.program.id)

      assert ParticipantRepository.is_participant?(conversation.id, ctx.staff_user.id)

      # 4. Staff can send a message
      assert {:ok, message} =
               Messaging.send_message(conversation.id, ctx.staff_user.id, "Hello from staff!")

      assert message.content == "Hello from staff!"

      # 5. Unassign staff (and drive the handler directly as above)
      assert {:ok, unassigned} =
               Provider.unassign_staff_from_program(ctx.program.id, ctx.staff.id)

      assert :ok =
               StaffAssignmentHandler.handle_event(
                 build_unassignment_event(
                   ctx.provider.id,
                   ctx.program.id,
                   unassigned.staff_member_id,
                   ctx.staff_user.id
                 )
               )

      # 6. Staff is no longer an active participant — #817 closes the
      #    inbox-visibility gap symmetrically: on unassignment the handler
      #    soft-leaves the participant row (sets `left_at` via leave/2; the
      #    row is preserved so re-assignment can re-activate it) and emits
      #    :participant_removed so the projection archives the staff's
      #    summary row.
      refute ParticipantRepository.is_participant?(conversation.id, ctx.staff_user.id)

      # 7. And projection is deactivated
      assert [] = ProgramStaffParticipantRepository.get_active_staff_user_ids(ctx.program.id)
    end
  end

  defp build_provider_scope(provider_schema, user) do
    provider_profile = %ProviderProfile{
      id: provider_schema.id,
      identity_id: user.id,
      business_name: provider_schema.business_name,
      subscription_tier: :professional
    }

    %Scope{
      user: user,
      roles: [:provider],
      provider: provider_profile,
      parent: nil
    }
  end

  defp build_assignment_event(provider_id, program_id, staff_member_id, staff_user_id) do
    %IntegrationEvent{
      event_id: Ecto.UUID.generate(),
      event_type: :staff_assigned_to_program,
      source_context: :provider,
      entity_type: :staff_member,
      entity_id: staff_member_id,
      occurred_at: DateTime.utc_now(),
      payload: %{
        provider_id: provider_id,
        program_id: program_id,
        staff_member_id: staff_member_id,
        staff_user_id: staff_user_id,
        assigned_at: DateTime.utc_now()
      }
    }
  end

  defp build_unassignment_event(provider_id, program_id, staff_member_id, staff_user_id) do
    %IntegrationEvent{
      event_id: Ecto.UUID.generate(),
      event_type: :staff_unassigned_from_program,
      source_context: :provider,
      entity_type: :staff_member,
      entity_id: staff_member_id,
      occurred_at: DateTime.utc_now(),
      payload: %{
        provider_id: provider_id,
        program_id: program_id,
        staff_member_id: staff_member_id,
        staff_user_id: staff_user_id,
        unassigned_at: DateTime.utc_now()
      }
    }
  end
end
