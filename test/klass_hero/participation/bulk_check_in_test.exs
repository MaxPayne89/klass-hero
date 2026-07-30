defmodule KlassHero.Participation.BulkCheckInTest do
  @moduledoc """
  Tests for BulkCheckIn use case.

  Verifies the bulk check-in business rules:
  - All registered records check in successfully
  - Partial success is allowed (some succeed, some fail)
  - Non-existent record IDs go to the failed list
  - Notes are applied to all successful check-ins
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.EventTestHelper
  alias KlassHero.Participation.ParticipationRecord

  setup do
    EventTestHelper.setup_test_integration_events()
    :ok
  end

  # The user fixtures stage `user_registered`, so filter to the event under test
  # rather than asserting on everything the process emitted.
  defp check_in_events do
    Enum.filter(EventTestHelper.get_published_integration_events(), &(&1.event_type == :child_checked_in))
  end

  describe "execute/1" do
    test "returns empty result for empty record_ids list" do
      staff_id = AccountsFixtures.unconfirmed_user_fixture().id

      result = KlassHero.Participation.bulk_check_in(%{record_ids: [], checked_in_by: staff_id})

      assert result == %{successful: [], failed: []}
    end

    test "successfully checks in all registered records" do
      session = insert(:program_session_schema, status: :in_progress)
      child_a = insert(:child_schema)
      child_b = insert(:child_schema)
      staff_id = AccountsFixtures.unconfirmed_user_fixture().id

      record_a =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child_a.id,
          status: :registered
        )

      record_b =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child_b.id,
          status: :registered
        )

      result =
        KlassHero.Participation.bulk_check_in(%{
          record_ids: [record_a.id, record_b.id],
          checked_in_by: staff_id
        })

      assert length(result.successful) == 2
      assert result.failed == []

      ids = Enum.map(result.successful, & &1.id)
      assert record_a.id in ids
      assert record_b.id in ids

      for record <- result.successful do
        assert %ParticipationRecord{} = record
        assert record.status == :checked_in
        assert record.check_in_by == staff_id
        assert record.check_in_at != nil
      end
    end

    test "applies notes to all successfully checked-in records" do
      session = insert(:program_session_schema, status: :in_progress)
      child = insert(:child_schema)
      staff_id = AccountsFixtures.unconfirmed_user_fixture().id

      record =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          status: :registered
        )

      result =
        KlassHero.Participation.bulk_check_in(%{
          record_ids: [record.id],
          checked_in_by: staff_id,
          notes: "Arrived with parent"
        })

      assert [checked_in] = result.successful
      assert checked_in.check_in_notes == "Arrived with parent"
    end

    test "partial success: checked-in records fail, registered records succeed" do
      session = insert(:program_session_schema, status: :in_progress)
      child_a = insert(:child_schema)
      child_b = insert(:child_schema)
      staff_id = AccountsFixtures.unconfirmed_user_fixture().id

      already_checked_in =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child_a.id,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: AccountsFixtures.unconfirmed_user_fixture().id
        )

      registered =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child_b.id,
          status: :registered
        )

      result =
        KlassHero.Participation.bulk_check_in(%{
          record_ids: [already_checked_in.id, registered.id],
          checked_in_by: staff_id
        })

      assert length(result.successful) == 1
      assert length(result.failed) == 1

      assert hd(result.successful).id == registered.id
      assert {failed_id, :invalid_status_transition} = hd(result.failed)
      assert failed_id == already_checked_in.id
    end

    test "non-existent record ID goes to failed list" do
      non_existent_id = Ecto.UUID.generate()
      staff_id = AccountsFixtures.unconfirmed_user_fixture().id

      result =
        KlassHero.Participation.bulk_check_in(%{
          record_ids: [non_existent_id],
          checked_in_by: staff_id
        })

      assert result.successful == []
      assert [{^non_existent_id, :not_found}] = result.failed
    end

    test "preserves input order in successful results" do
      session = insert(:program_session_schema, status: :in_progress)
      staff_id = AccountsFixtures.unconfirmed_user_fixture().id

      records =
        for _ <- 1..3 do
          insert(:participation_record_schema,
            session_id: session.id,
            child_id: insert(:child_schema).id,
            status: :registered
          )
        end

      ids = Enum.map(records, & &1.id)

      result = KlassHero.Participation.bulk_check_in(%{record_ids: ids, checked_in_by: staff_id})

      assert length(result.successful) == 3
      assert Enum.map(result.successful, & &1.id) == ids
    end

    test "publishes child_checked_in event for each successful check-in" do
      session = insert(:program_session_schema, status: :in_progress)
      child_a = insert(:child_schema)
      child_b = insert(:child_schema)
      staff_id = AccountsFixtures.unconfirmed_user_fixture().id

      record_a =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child_a.id,
          status: :registered
        )

      record_b =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child_b.id,
          status: :registered
        )

      KlassHero.Participation.bulk_check_in(%{
        record_ids: [record_a.id, record_b.id],
        checked_in_by: staff_id
      })

      staged = check_in_events()

      for record <- [record_a, record_b] do
        assert Enum.any?(
                 staged,
                 &(&1.payload.record_id == record.id and &1.payload.checked_in_by == staff_id)
               ),
               "expected a child_checked_in for #{record.id}"
      end
    end

    test "does not publish events for failed check-ins" do
      session = insert(:program_session_schema, status: :in_progress)
      child = insert(:child_schema)
      staff_id = AccountsFixtures.unconfirmed_user_fixture().id

      already_checked_in =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: AccountsFixtures.unconfirmed_user_fixture().id
        )

      KlassHero.Participation.bulk_check_in(%{
        record_ids: [already_checked_in.id],
        checked_in_by: staff_id
      })

      assert check_in_events() == []
    end
  end
end
