defmodule KlassHero.Participation.Adapters.Driven.Persistence.Repositories.ParticipationRepositoryTest do
  @moduledoc """
  Integration tests for ParticipationRepository.

  Tests database operations for participation record persistence including
  creation, retrieval, updates, batch operations, and optimistic locking.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation.Adapters.Driven.Persistence.Repositories.ParticipationRepository
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Repo

  describe "create/1" do
    test "successfully creates participation record and returns domain entity" do
      session = insert(:program_session_schema)
      child = insert(:child_schema)

      record =
        build(:participation_record,
          session_id: session.id,
          child_id: child.id
        )

      assert {:ok, created} = ParticipationRepository.create(record)
      assert %ParticipationRecord{} = created
      assert created.session_id == session.id
      assert created.child_id == child.id
      assert created.status == :registered
    end

    test "allows same child in different sessions" do
      session1 = insert(:program_session_schema)
      session2 = insert(:program_session_schema)
      child = insert(:child_schema)

      record1 = build(:participation_record, session_id: session1.id, child_id: child.id)
      record2 = build(:participation_record, session_id: session2.id, child_id: child.id)

      assert {:ok, _} = ParticipationRepository.create(record1)
      assert {:ok, _} = ParticipationRepository.create(record2)
    end
  end

  describe "get_by_id/1" do
    test "returns record when found" do
      record_schema = insert(:participation_record_schema)

      assert {:ok, record} = ParticipationRepository.get_by_id(record_schema.id)
      assert %ParticipationRecord{} = record
      assert record.id == record_schema.id
    end

    test "returns error when record not found" do
      non_existent_id = Ecto.UUID.generate()

      assert {:error, :not_found} = ParticipationRepository.get_by_id(non_existent_id)
    end
  end

  describe "update/1" do
    test "successfully updates record status" do
      record_schema = insert(:participation_record_schema, status: :registered)
      domain_record = record_schema
      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      {:ok, checked_in} = ParticipationRecord.check_in(domain_record, user.id)

      assert {:ok, result} = ParticipationRepository.update(checked_in)
      assert result.status == :checked_in
    end

    test "returns error when record not found" do
      non_existent_record = build(:participation_record, id: Ecto.UUID.generate())

      assert {:error, :not_found} = ParticipationRepository.update(non_existent_record)
    end

    test "updates check-in information" do
      record_schema = insert(:participation_record_schema, status: :registered)
      domain_record = record_schema
      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      {:ok, checked_in} =
        ParticipationRecord.check_in(domain_record, user.id, "Arrived on time")

      assert {:ok, result} = ParticipationRepository.update(checked_in)
      assert result.status == :checked_in
      assert result.check_in_notes == "Arrived on time"
      assert result.check_in_by == user.id
    end

    test "updates check-out information" do
      check_in_user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      record_schema =
        insert(:participation_record_schema,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: check_in_user.id
        )

      domain_record = record_schema
      check_out_user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      {:ok, checked_out} =
        ParticipationRecord.check_out(domain_record, check_out_user.id, "Picked up by parent")

      assert {:ok, result} = ParticipationRepository.update(checked_out)
      assert result.status == :checked_out
      assert result.check_out_notes == "Picked up by parent"
      assert result.check_out_by == check_out_user.id
    end

    test "handles optimistic locking conflict" do
      record_schema = insert(:participation_record_schema)

      # Simulate two processes fetching the same record
      domain_v1_a = record_schema
      domain_v1_b = record_schema

      # First update succeeds
      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()
      {:ok, updated_a} = ParticipationRecord.check_in(domain_v1_a, user.id)
      assert {:ok, _} = ParticipationRepository.update(updated_a)

      # Second update fails with stale data
      {:ok, updated_b} = ParticipationRecord.mark_absent(domain_v1_b)
      assert {:error, :stale_data} = ParticipationRepository.update(updated_b)

      # Verify first update persisted
      final_schema = Repo.get(ParticipationRecord, record_schema.id)
      assert final_schema.status == :checked_in
    end

    test "sequential updates with version increments succeed" do
      record_schema = insert(:participation_record_schema)
      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      # First update
      domain_v1 = record_schema
      {:ok, checked_in} = ParticipationRecord.check_in(domain_v1, user.id)
      assert {:ok, result_v2} = ParticipationRepository.update(checked_in)

      # Second update using fresh result
      {:ok, checked_out} = ParticipationRecord.check_out(result_v2, user.id)
      assert {:ok, result_v3} = ParticipationRepository.update(checked_out)

      assert result_v3.status == :checked_out
    end
  end

  describe "list_by_session/1" do
    test "returns all records for session" do
      session = insert(:program_session_schema)
      child1 = insert(:child_schema)
      child2 = insert(:child_schema)

      insert(:participation_record_schema, session_id: session.id, child_id: child1.id)
      insert(:participation_record_schema, session_id: session.id, child_id: child2.id)

      records = ParticipationRepository.list_by_session(session.id)
      assert length(records) == 2
      assert Enum.all?(records, &(&1.session_id == session.id))
    end

    test "returns empty list when session has no records" do
      session = insert(:program_session_schema)

      assert [] = ParticipationRepository.list_by_session(session.id)
    end

    test "does not return records from other sessions" do
      session1 = insert(:program_session_schema)
      session2 = insert(:program_session_schema)
      child = insert(:child_schema)

      insert(:participation_record_schema, session_id: session1.id, child_id: child.id)
      insert(:participation_record_schema, session_id: session2.id, child_id: child.id)

      records = ParticipationRepository.list_by_session(session1.id)
      assert length(records) == 1
      assert hd(records).session_id == session1.id
    end
  end

  describe "list_by_child/1" do
    test "returns all records for child" do
      child = insert(:child_schema)
      session1 = insert(:program_session_schema)
      session2 = insert(:program_session_schema)

      insert(:participation_record_schema, session_id: session1.id, child_id: child.id)
      insert(:participation_record_schema, session_id: session2.id, child_id: child.id)

      records = ParticipationRepository.list_by_child(child.id)
      assert length(records) == 2
      assert Enum.all?(records, &(&1.child_id == child.id))
    end

    test "returns empty list when child has no records" do
      child = insert(:child_schema)

      assert [] = ParticipationRepository.list_by_child(child.id)
    end
  end

  describe "list_by_children/1" do
    test "returns all records for multiple children" do
      child1 = insert(:child_schema)
      child2 = insert(:child_schema)
      session = insert(:program_session_schema)

      insert(:participation_record_schema, session_id: session.id, child_id: child1.id)
      insert(:participation_record_schema, session_id: session.id, child_id: child2.id)

      records = ParticipationRepository.list_by_children([child1.id, child2.id])
      assert length(records) == 2
    end

    test "returns empty list for empty child list" do
      assert [] = ParticipationRepository.list_by_children([])
    end
  end

  describe "create_batch/1" do
    test "creates multiple records in single transaction" do
      session = insert(:program_session_schema)
      child1 = insert(:child_schema)
      child2 = insert(:child_schema)

      record1 = build(:participation_record, session_id: session.id, child_id: child1.id)
      record2 = build(:participation_record, session_id: session.id, child_id: child2.id)

      assert {:ok, records} = ParticipationRepository.create_batch([record1, record2])
      assert length(records) == 2
      assert Enum.all?(records, &match?(%ParticipationRecord{}, &1))
    end

    test "returns empty list for empty input" do
      assert {:ok, []} = ParticipationRepository.create_batch([])
    end
  end

  describe "list_by_session_with_session/1" do
    test "returns records with session data" do
      session = insert(:program_session_schema)
      child = insert(:child_schema)

      insert(:participation_record_schema, session_id: session.id, child_id: child.id)

      results = ParticipationRepository.list_by_session_with_session(session.id)
      assert length(results) == 1

      [{record, session_schema}] = results
      assert %ParticipationRecord{} = record
      assert session_schema.id == session.id
    end

    test "returns empty list when no records exist" do
      session = insert(:program_session_schema)

      assert [] = ParticipationRepository.list_by_session_with_session(session.id)
    end
  end
end
