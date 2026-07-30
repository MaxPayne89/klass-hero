defmodule KlassHero.Messaging.Adapters.Driving.Events.StaffAssignmentHandlerTest do
  use KlassHero.DataCase, async: false

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ProgramStaffParticipantRepository
  alias KlassHero.Messaging.Adapters.Driving.Events.StaffAssignmentHandler
  alias KlassHero.Shared.Domain.Events.Event

  setup do
    setup_test_integration_events()
    :ok
  end

  describe "handle_event/1 - staff_assigned_to_program" do
    test "upserts projection when staff_user_id is present" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      staff_user_id = Ecto.UUID.generate()

      event = build_assignment_event(provider.id, program.id, staff_user_id)
      assert :ok = StaffAssignmentHandler.handle_event(event)

      assert [^staff_user_id] =
               ProgramStaffParticipantRepository.get_active_staff_user_ids(program.id)
    end

    test "skips when staff_user_id is nil" do
      event = build_assignment_event(Ecto.UUID.generate(), Ecto.UUID.generate(), nil)
      assert :ok = StaffAssignmentHandler.handle_event(event)
    end

    test "adds staff to existing active conversations for the program" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      parent_user = KlassHero.AccountsFixtures.user_fixture()
      staff_user = KlassHero.AccountsFixtures.user_fixture()
      staff_user_id = staff_user.id

      # Create existing conversation for this program
      conversation =
        insert(:conversation_schema,
          provider_id: provider.id,
          type: "direct",
          program_id: program.id
        )

      insert(:participant_schema, conversation_id: conversation.id, user_id: parent_user.id)

      event = build_assignment_event(provider.id, program.id, staff_user_id)
      assert :ok = StaffAssignmentHandler.handle_event(event)

      # Staff should now be a participant
      assert KlassHero.Messaging.participant?(conversation.id, staff_user_id)
    end

    test "emits :participant_added per back-filled conversation with source :later_assignment" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      parent_user = KlassHero.AccountsFixtures.user_fixture()
      staff_user = KlassHero.AccountsFixtures.user_fixture()

      conv_a =
        insert(:conversation_schema,
          provider_id: provider.id,
          type: "direct",
          program_id: program.id
        )

      conv_b =
        insert(:conversation_schema,
          provider_id: provider.id,
          type: "direct",
          program_id: program.id
        )

      insert(:participant_schema, conversation_id: conv_a.id, user_id: parent_user.id)
      insert(:participant_schema, conversation_id: conv_b.id, user_id: parent_user.id)

      event = build_assignment_event(provider.id, program.id, staff_user.id)
      assert :ok = StaffAssignmentHandler.handle_event(event)

      events =
        Enum.filter(
          get_published_integration_events(),
          &(&1.event_type == :participant_added)
        )

      assert length(events) == 2
      conv_ids = events |> Enum.map(& &1.entity_id) |> Enum.sort()
      assert conv_ids == Enum.sort([conv_a.id, conv_b.id])

      assert Enum.all?(events, fn e ->
               e.payload.participant_user_ids == [staff_user.id] and
                 e.payload.source == "later_assignment"
             end)
    end

    test "emits no :participant_added when staff is already in every program conversation" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      staff_user = KlassHero.AccountsFixtures.user_fixture()

      conv =
        insert(:conversation_schema,
          provider_id: provider.id,
          type: "direct",
          program_id: program.id
        )

      insert(:participant_schema, conversation_id: conv.id, user_id: staff_user.id)

      event = build_assignment_event(provider.id, program.id, staff_user.id)
      assert :ok = StaffAssignmentHandler.handle_event(event)

      refute Enum.any?(
               get_published_integration_events(),
               &(&1.event_type == :participant_added)
             )
    end
  end

  describe "handle_event/1 - staff_unassigned_from_program" do
    test "deactivates projection entry" do
      provider_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()
      staff_user_id = Ecto.UUID.generate()

      ProgramStaffParticipantRepository.upsert_active(%{
        provider_id: provider_id,
        program_id: program_id,
        staff_user_id: staff_user_id
      })

      event = build_unassignment_event(provider_id, program_id, staff_user_id)
      assert :ok = StaffAssignmentHandler.handle_event(event)

      assert [] = ProgramStaffParticipantRepository.get_active_staff_user_ids(program_id)
    end

    test "removes staff from active program conversations and emits :participant_removed per conversation" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      parent_user = KlassHero.AccountsFixtures.user_fixture()
      staff_user = KlassHero.AccountsFixtures.user_fixture()

      ProgramStaffParticipantRepository.upsert_active(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff_user.id
      })

      conv_a =
        insert(:conversation_schema,
          provider_id: provider.id,
          type: "direct",
          program_id: program.id
        )

      conv_b =
        insert(:conversation_schema,
          provider_id: provider.id,
          type: "direct",
          program_id: program.id
        )

      insert(:participant_schema, conversation_id: conv_a.id, user_id: parent_user.id)
      insert(:participant_schema, conversation_id: conv_a.id, user_id: staff_user.id)
      insert(:participant_schema, conversation_id: conv_b.id, user_id: parent_user.id)
      insert(:participant_schema, conversation_id: conv_b.id, user_id: staff_user.id)

      event = build_unassignment_event(provider.id, program.id, staff_user.id)
      assert :ok = StaffAssignmentHandler.handle_event(event)

      refute KlassHero.Messaging.participant?(conv_a.id, staff_user.id)
      refute KlassHero.Messaging.participant?(conv_b.id, staff_user.id)

      events =
        Enum.filter(
          get_published_integration_events(),
          &(&1.event_type == :participant_removed)
        )

      assert length(events) == 2

      assert Enum.all?(events, fn e ->
               e.payload.participant_user_ids == [staff_user.id] and
                 e.payload.source == "staff_unassignment"
             end)
    end
  end

  defp build_assignment_event(provider_id, program_id, staff_user_id) do
    %Event{
      event_id: Ecto.UUID.generate(),
      event_type: :staff_assigned_to_program,
      source_context: :provider,
      entity_type: :staff_member,
      entity_id: Ecto.UUID.generate(),
      occurred_at: DateTime.utc_now(),
      payload: %{
        provider_id: provider_id,
        program_id: program_id,
        staff_member_id: Ecto.UUID.generate(),
        staff_user_id: staff_user_id,
        assigned_at: DateTime.utc_now()
      }
    }
  end

  defp build_unassignment_event(provider_id, program_id, staff_user_id) do
    %Event{
      event_id: Ecto.UUID.generate(),
      event_type: :staff_unassigned_from_program,
      source_context: :provider,
      entity_type: :staff_member,
      entity_id: Ecto.UUID.generate(),
      occurred_at: DateTime.utc_now(),
      payload: %{
        provider_id: provider_id,
        program_id: program_id,
        staff_member_id: Ecto.UUID.generate(),
        staff_user_id: staff_user_id,
        unassigned_at: DateTime.utc_now()
      }
    }
  end
end
