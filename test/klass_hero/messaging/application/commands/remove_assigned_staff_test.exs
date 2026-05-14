defmodule KlassHero.Messaging.Application.Commands.RemoveAssignedStaffTest do
  use KlassHero.DataCase, async: false

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ParticipantRepository
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSchema
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ParticipantSchema
  alias KlassHero.Messaging.Application.Commands.RemoveAssignedStaff
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.DomainEvent

  setup do
    setup_test_integration_events()
    :ok
  end

  describe "execute/2 — events-as-data contract" do
    test "returns {:ok, {removals, events}} and does NOT dispatch the events itself" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      staff = AccountsFixtures.user_fixture()
      parent_a = AccountsFixtures.user_fixture()
      parent_b = AccountsFixtures.user_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      conv_a = insert_conversation(provider.id, program.id)
      conv_b = insert_conversation(provider.id, program.id)
      insert_participant(conv_a, staff.id, now)
      insert_participant(conv_a, parent_a.id, now)
      insert_participant(conv_b, staff.id, now)
      insert_participant(conv_b, parent_b.id, now)

      assert {:ok, {:ok, {removed, events}}} =
               Repo.transaction(fn ->
                 RemoveAssignedStaff.execute(program.id, staff.id)
               end)

      assert Enum.sort(Enum.map(removed, & &1.conversation_id)) ==
               Enum.sort([conv_a, conv_b])

      refute ParticipantRepository.is_participant?(conv_a, staff.id)
      refute ParticipantRepository.is_participant?(conv_b, staff.id)

      assert length(events) == 2
      assert Enum.all?(events, &match?(%DomainEvent{event_type: :participant_removed}, &1))

      event_conv_ids = events |> Enum.map(& &1.aggregate_id) |> Enum.sort()
      assert event_conv_ids == Enum.sort([conv_a, conv_b])

      assert Enum.all?(events, fn e ->
               e.payload.participant_user_ids == [staff.id] and
                 e.payload.source == :staff_unassignment
             end)

      # Critical: events are returned as data, NOT dispatched in-band.
      refute Enum.any?(
               get_published_integration_events(),
               &(&1.event_type == :participant_removed)
             )
    end

    test "staff in zero conversations — returns {:ok, {[], []}}" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      staff = AccountsFixtures.user_fixture()

      assert {:ok, {:ok, {[], []}}} =
               Repo.transaction(fn ->
                 RemoveAssignedStaff.execute(program.id, staff.id)
               end)
    end

    test "skips archived conversations" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      staff = AccountsFixtures.user_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      archived_conv = insert_conversation(provider.id, program.id, archived_at: now)
      insert_participant(archived_conv, staff.id, now)

      assert {:ok, {:ok, {[], []}}} =
               Repo.transaction(fn ->
                 RemoveAssignedStaff.execute(program.id, staff.id)
               end)

      assert ParticipantRepository.is_participant?(archived_conv, staff.id)
    end

    test "leaves non-program conversations alone" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      other_program = insert(:program_schema, provider_id: provider.id)
      staff = AccountsFixtures.user_fixture()
      parent = AccountsFixtures.user_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      target_conv = insert_conversation(provider.id, program.id)
      other_conv = insert_conversation(provider.id, other_program.id)
      insert_participant(target_conv, staff.id, now)
      insert_participant(target_conv, parent.id, now)
      insert_participant(other_conv, staff.id, now)

      assert {:ok, {:ok, {removed, [event]}}} =
               Repo.transaction(fn ->
                 RemoveAssignedStaff.execute(program.id, staff.id)
               end)

      assert Enum.map(removed, & &1.conversation_id) == [target_conv]
      assert event.aggregate_id == target_conv
      refute ParticipantRepository.is_participant?(target_conv, staff.id)
      assert ParticipantRepository.is_participant?(other_conv, staff.id)
    end
  end

  defp insert_conversation(provider_id, program_id, opts \\ []) do
    id = Ecto.UUID.generate()

    Repo.insert!(%ConversationSchema{
      id: id,
      type: "direct",
      provider_id: provider_id,
      program_id: program_id,
      archived_at: Keyword.get(opts, :archived_at)
    })

    id
  end

  defp insert_participant(conversation_id, user_id, joined_at) do
    Repo.insert!(%ParticipantSchema{
      id: Ecto.UUID.generate(),
      conversation_id: conversation_id,
      user_id: user_id,
      joined_at: joined_at
    })
  end
end
