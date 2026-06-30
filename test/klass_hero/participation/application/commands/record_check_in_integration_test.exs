defmodule KlassHero.Participation.Application.Commands.RecordCheckInIntegrationTest do
  @moduledoc """
  Integration tests for RecordCheckIn and RecordCheckOut use cases.

  These tests verify the use cases work correctly with real repositories.

  Test Coverage:
  - Check-in transitions record to checked_in status
  - Check-out transitions record to checked_out status
  - Events are published with correct payload structure
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Shared.Adapters.Driven.Events.TestEventPublisher

  setup do
    TestEventPublisher.setup()
    :ok
  end

  describe "RecordCheckIn integration" do
    test "checks in a registered record and publishes event" do
      record_schema = insert(:participation_record_schema)
      staff_id = AccountsFixtures.unconfirmed_user_fixture().id

      {:ok, record} =
        KlassHero.Participation.record_check_in(%{
          record_id: record_schema.id,
          checked_in_by: staff_id,
          notes: "Arrived on time"
        })

      assert record.status == :checked_in
      assert record.check_in_by == staff_id
      assert record.check_in_notes == "Arrived on time"
      assert %DateTime{} = record.check_in_at

      # Dual-topic publishing: one publish per topic (generic + provider-specific)
      events = TestEventPublisher.get_events()
      assert Enum.any?(events, &(&1.event_type == :child_checked_in))

      event = Enum.find(events, &(&1.event_type == :child_checked_in))
      assert event.payload.record_id == record_schema.id
      assert event.payload.session_id == record_schema.session_id
      assert event.payload.child_id == record_schema.child_id
      assert event.payload.checked_in_by == staff_id
      assert event.payload.notes == "Arrived on time"
      assert %DateTime{} = event.payload.checked_in_at
    end

    test "checks in with nil notes" do
      record_schema = insert(:participation_record_schema)
      staff_id = AccountsFixtures.unconfirmed_user_fixture().id

      {:ok, record} =
        KlassHero.Participation.record_check_in(%{
          record_id: record_schema.id,
          checked_in_by: staff_id
        })

      assert record.status == :checked_in
      assert record.check_in_notes == nil

      events = TestEventPublisher.get_events()
      event = hd(events)
      assert event.payload.notes == nil
    end

    test "returns error for non-existent record" do
      fake_id = Ecto.UUID.generate()

      result =
        KlassHero.Participation.record_check_in(%{
          record_id: fake_id,
          checked_in_by: AccountsFixtures.unconfirmed_user_fixture().id
        })

      assert {:error, :not_found} = result
      assert TestEventPublisher.get_events() == []
    end

    test "returns error when checking in already checked-in record" do
      record_schema =
        insert(:participation_record_schema,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: AccountsFixtures.unconfirmed_user_fixture().id
        )

      staff_id = AccountsFixtures.unconfirmed_user_fixture().id

      result =
        KlassHero.Participation.record_check_in(%{
          record_id: record_schema.id,
          checked_in_by: staff_id
        })

      assert {:error, :invalid_status_transition} = result
      assert TestEventPublisher.get_events() == []
    end
  end

  describe "RecordCheckOut integration" do
    test "checks out a checked-in record and publishes event" do
      record_schema =
        insert(:participation_record_schema,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: AccountsFixtures.unconfirmed_user_fixture().id
        )

      staff_id = AccountsFixtures.unconfirmed_user_fixture().id

      {:ok, record} =
        KlassHero.Participation.record_check_out(%{
          record_id: record_schema.id,
          checked_out_by: staff_id,
          notes: "Picked up by parent"
        })

      assert record.status == :checked_out
      assert record.check_out_by == staff_id
      assert record.check_out_notes == "Picked up by parent"
      assert %DateTime{} = record.check_out_at

      # Dual-topic publishing: one publish per topic (generic + provider-specific)
      events = TestEventPublisher.get_events()
      assert Enum.any?(events, &(&1.event_type == :child_checked_out))

      event = Enum.find(events, &(&1.event_type == :child_checked_out))
      assert event.payload.record_id == record_schema.id
      assert event.payload.session_id == record_schema.session_id
      assert event.payload.child_id == record_schema.child_id
      assert event.payload.checked_out_by == staff_id
      assert event.payload.notes == "Picked up by parent"
      assert %DateTime{} = event.payload.checked_out_at
    end

    test "checks out with nil notes" do
      record_schema =
        insert(:participation_record_schema,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: AccountsFixtures.unconfirmed_user_fixture().id
        )

      staff_id = AccountsFixtures.unconfirmed_user_fixture().id

      {:ok, record} =
        KlassHero.Participation.record_check_out(%{
          record_id: record_schema.id,
          checked_out_by: staff_id
        })

      assert record.status == :checked_out
      assert record.check_out_notes == nil

      events = TestEventPublisher.get_events()
      event = hd(events)
      assert event.payload.notes == nil
    end

    test "returns error for non-existent record" do
      fake_id = Ecto.UUID.generate()

      result =
        KlassHero.Participation.record_check_out(%{
          record_id: fake_id,
          checked_out_by: AccountsFixtures.unconfirmed_user_fixture().id
        })

      assert {:error, :not_found} = result
      assert TestEventPublisher.get_events() == []
    end

    test "returns error when checking out a registered record" do
      record_schema = insert(:participation_record_schema)
      staff_id = AccountsFixtures.unconfirmed_user_fixture().id

      result =
        KlassHero.Participation.record_check_out(%{
          record_id: record_schema.id,
          checked_out_by: staff_id
        })

      assert {:error, :invalid_status_transition} = result
      assert TestEventPublisher.get_events() == []
    end
  end

  describe "end-to-end check-in/check-out flow" do
    test "complete participation cycle" do
      record_schema = insert(:participation_record_schema)
      staff_id = AccountsFixtures.unconfirmed_user_fixture().id

      # Check in
      {:ok, check_in_record} =
        KlassHero.Participation.record_check_in(%{
          record_id: record_schema.id,
          checked_in_by: staff_id,
          notes: "Morning arrival"
        })

      assert check_in_record.status == :checked_in

      # Check out
      {:ok, check_out_record} =
        KlassHero.Participation.record_check_out(%{
          record_id: record_schema.id,
          checked_out_by: staff_id,
          notes: "Evening pickup"
        })

      assert check_out_record.status == :checked_out

      # Verify both events were published (dual-topic: each event appears per topic)
      events = TestEventPublisher.get_events()
      assert Enum.any?(events, &(&1.event_type == :child_checked_in))
      assert Enum.any?(events, &(&1.event_type == :child_checked_out))

      check_in_event = Enum.find(events, &(&1.event_type == :child_checked_in))
      check_out_event = Enum.find(events, &(&1.event_type == :child_checked_out))

      assert check_in_event.payload.notes == "Morning arrival"
      assert check_out_event.payload.notes == "Evening pickup"
    end
  end
end
