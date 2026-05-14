defmodule KlassHero.Messaging.Application.Commands.AddAssignedStaffTest do
  use KlassHero.DataCase, async: false

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ParticipantRepository
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ProgramStaffParticipantRepository
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSchema
  alias KlassHero.Messaging.Application.Commands.AddAssignedStaff
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.DomainEvent

  setup do
    setup_test_integration_events()
    :ok
  end

  describe "execute/3 — events-as-data contract" do
    test "returns {:ok, {added_ids, [DomainEvent]}} and does NOT dispatch the event itself" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      owner = AccountsFixtures.user_fixture()
      staff_a = AccountsFixtures.user_fixture()
      staff_b = AccountsFixtures.user_fixture()

      ProgramStaffParticipantRepository.upsert_active(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff_a.id
      })

      ProgramStaffParticipantRepository.upsert_active(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff_b.id
      })

      conversation_id = Ecto.UUID.generate()

      Repo.insert!(%ConversationSchema{
        id: conversation_id,
        type: "direct",
        provider_id: provider.id,
        program_id: program.id
      })

      assert {:ok, {:ok, {added_ids, events}}} =
               Repo.transaction(fn ->
                 AddAssignedStaff.execute(conversation_id, program.id, owner.id)
               end)

      assert Enum.sort(added_ids) == Enum.sort([staff_a.id, staff_b.id])
      assert ParticipantRepository.is_participant?(conversation_id, staff_a.id)
      assert ParticipantRepository.is_participant?(conversation_id, staff_b.id)

      assert [%DomainEvent{} = event] = events
      assert event.event_type == :participant_added
      assert event.aggregate_id == conversation_id
      assert event.aggregate_type == :conversation
      assert Enum.sort(event.payload.participant_user_ids) == Enum.sort([staff_a.id, staff_b.id])
      assert event.payload.source == :initial_staff

      # Critical: the command must NOT dispatch the event itself —
      # post-commit dispatch is the caller's responsibility so the projection
      # can read-your-own-writes after Repo.transaction commits.
      refute Enum.any?(
               get_published_integration_events(),
               &(&1.event_type == :participant_added)
             )
    end

    test "excludes the owner from participant additions and from event payload" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      owner = AccountsFixtures.user_fixture()
      staff = AccountsFixtures.user_fixture()

      ProgramStaffParticipantRepository.upsert_active(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: owner.id
      })

      ProgramStaffParticipantRepository.upsert_active(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff.id
      })

      conversation_id = Ecto.UUID.generate()

      Repo.insert!(%ConversationSchema{
        id: conversation_id,
        type: "direct",
        provider_id: provider.id,
        program_id: program.id
      })

      assert {:ok, {:ok, {added_ids, [event]}}} =
               Repo.transaction(fn ->
                 AddAssignedStaff.execute(conversation_id, program.id, owner.id)
               end)

      assert added_ids == [staff.id]
      refute ParticipantRepository.is_participant?(conversation_id, owner.id)
      assert event.payload.participant_user_ids == [staff.id]
    end

    test "no staff assigned to program — returns {:ok, {[], []}} and no events" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      owner = AccountsFixtures.user_fixture()

      conversation_id = Ecto.UUID.generate()

      Repo.insert!(%ConversationSchema{
        id: conversation_id,
        type: "direct",
        provider_id: provider.id,
        program_id: program.id
      })

      assert {:ok, {:ok, {[], []}}} =
               Repo.transaction(fn ->
                 AddAssignedStaff.execute(conversation_id, program.id, owner.id)
               end)
    end

    test "nil program_id — returns {:ok, {[], []}} immediately" do
      owner = AccountsFixtures.user_fixture()
      conversation_id = Ecto.UUID.generate()

      assert {:ok, {[], []}} = AddAssignedStaff.execute(conversation_id, nil, owner.id)
    end

    test "owner is the only staff member — returns {:ok, {[], []}}" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      owner = AccountsFixtures.user_fixture()

      ProgramStaffParticipantRepository.upsert_active(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: owner.id
      })

      conversation_id = Ecto.UUID.generate()

      Repo.insert!(%ConversationSchema{
        id: conversation_id,
        type: "direct",
        provider_id: provider.id,
        program_id: program.id
      })

      assert {:ok, {:ok, {[], []}}} =
               Repo.transaction(fn ->
                 AddAssignedStaff.execute(conversation_id, program.id, owner.id)
               end)
    end
  end
end
