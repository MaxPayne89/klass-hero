defmodule KlassHero.Participation.ParticipationRecordTest do
  @moduledoc """
  Tests for ParticipationRecord domain entity.

  Covers validation, status transitions, and check-in/out flows.
  """

  use ExUnit.Case, async: true

  import KlassHero.Factory

  alias KlassHero.Participation.ParticipationRecord

  describe "new/1" do
    test "creates a valid participation record with required fields" do
      attrs = %{
        id: Ecto.UUID.generate(),
        session_id: Ecto.UUID.generate(),
        child_id: Ecto.UUID.generate()
      }

      assert {:ok, record} = ParticipationRecord.new(attrs)
      assert record.id == attrs.id
      assert record.session_id == attrs.session_id
      assert record.child_id == attrs.child_id
      assert record.status == :registered
      assert record.lock_version == 1
    end

    test "creates record with optional fields" do
      parent_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      attrs = %{
        id: Ecto.UUID.generate(),
        session_id: Ecto.UUID.generate(),
        child_id: Ecto.UUID.generate(),
        parent_id: parent_id,
        provider_id: provider_id
      }

      assert {:ok, record} = ParticipationRecord.new(attrs)
      assert record.parent_id == parent_id
      assert record.provider_id == provider_id
    end

    test "returns error when id is missing" do
      attrs = %{
        session_id: Ecto.UUID.generate(),
        child_id: Ecto.UUID.generate()
      }

      assert {:error, :missing_required_fields} = ParticipationRecord.new(attrs)
    end

    test "returns error when session_id is missing" do
      attrs = %{
        id: Ecto.UUID.generate(),
        child_id: Ecto.UUID.generate()
      }

      assert {:error, :missing_required_fields} = ParticipationRecord.new(attrs)
    end

    test "returns error when child_id is missing" do
      attrs = %{
        id: Ecto.UUID.generate(),
        session_id: Ecto.UUID.generate()
      }

      assert {:error, :missing_required_fields} = ParticipationRecord.new(attrs)
    end
  end

  describe "check_in/3" do
    test "transitions :registered record to :checked_in" do
      record = build(:participation_record, status: :registered)
      provider_id = Ecto.UUID.generate()

      assert {:ok, checked_in} =
               ParticipationRecord.check_in(record, provider_id, "Arrived early")

      assert checked_in.status == :checked_in
      assert checked_in.check_in_by == provider_id
      assert checked_in.check_in_notes == "Arrived early"
      assert %DateTime{} = checked_in.check_in_at
    end

    test "allows nil notes" do
      record = build(:participation_record, status: :registered)
      provider_id = Ecto.UUID.generate()

      assert {:ok, checked_in} = ParticipationRecord.check_in(record, provider_id)

      assert checked_in.check_in_notes == nil
    end

    test "returns error when checking in already checked-in record" do
      record = build(:participation_record, status: :checked_in)
      provider_id = Ecto.UUID.generate()

      assert {:error, :invalid_status_transition} =
               ParticipationRecord.check_in(record, provider_id)
    end

    test "returns error when checking in checked-out record" do
      record = build(:participation_record, status: :checked_out)
      provider_id = Ecto.UUID.generate()

      assert {:error, :invalid_status_transition} =
               ParticipationRecord.check_in(record, provider_id)
    end

    test "returns error when checking in absent record" do
      record = build(:participation_record, status: :absent)
      provider_id = Ecto.UUID.generate()

      assert {:error, :invalid_status_transition} =
               ParticipationRecord.check_in(record, provider_id)
    end
  end

  describe "check_out/3" do
    test "transitions :checked_in record to :checked_out" do
      record =
        build(:participation_record,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: Ecto.UUID.generate()
        )

      provider_id = Ecto.UUID.generate()

      assert {:ok, checked_out} =
               ParticipationRecord.check_out(record, provider_id, "Picked up by mom")

      assert checked_out.status == :checked_out
      assert checked_out.check_out_by == provider_id
      assert checked_out.check_out_notes == "Picked up by mom"
      assert %DateTime{} = checked_out.check_out_at
    end

    test "allows nil notes" do
      record =
        build(:participation_record,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: Ecto.UUID.generate()
        )

      provider_id = Ecto.UUID.generate()

      assert {:ok, checked_out} = ParticipationRecord.check_out(record, provider_id)

      assert checked_out.check_out_notes == nil
    end

    test "returns error when checking out :registered record" do
      record = build(:participation_record, status: :registered)
      provider_id = Ecto.UUID.generate()

      assert {:error, :invalid_status_transition} =
               ParticipationRecord.check_out(record, provider_id)
    end

    test "returns error when checking out already checked-out record" do
      record = build(:participation_record, status: :checked_out)
      provider_id = Ecto.UUID.generate()

      assert {:error, :invalid_status_transition} =
               ParticipationRecord.check_out(record, provider_id)
    end

    test "returns error when checking out absent record" do
      record = build(:participation_record, status: :absent)
      provider_id = Ecto.UUID.generate()

      assert {:error, :invalid_status_transition} =
               ParticipationRecord.check_out(record, provider_id)
    end
  end

  describe "mark_absent/1" do
    test "transitions :registered record to :absent" do
      record = build(:participation_record, status: :registered)

      assert {:ok, absent} = ParticipationRecord.mark_absent(record)
      assert absent.status == :absent
    end

    test "returns error when marking :checked_in as absent" do
      record = build(:participation_record, status: :checked_in)

      assert {:error, :invalid_status_transition} = ParticipationRecord.mark_absent(record)
    end

    test "returns error when marking :checked_out as absent" do
      record = build(:participation_record, status: :checked_out)

      assert {:error, :invalid_status_transition} = ParticipationRecord.mark_absent(record)
    end

    test "returns error when marking :absent as absent" do
      record = build(:participation_record, status: :absent)

      assert {:error, :invalid_status_transition} = ParticipationRecord.mark_absent(record)
    end
  end

  describe "checked_in?/1" do
    for {status, expected} <- [
          {:checked_in, true},
          {:registered, false},
          {:checked_out, false},
          {:absent, false}
        ] do
      @status status
      @expected expected
      test "#{expected} for #{status} status" do
        record = build(:participation_record, status: @status)
        assert ParticipationRecord.checked_in?(record) == @expected
      end
    end
  end

  describe "completed?/1" do
    for {status, expected} <- [
          {:checked_out, true},
          {:registered, false},
          {:checked_in, false},
          {:absent, false}
        ] do
      @status status
      @expected expected
      test "#{expected} for #{status} status" do
        record = build(:participation_record, status: @status)
        assert ParticipationRecord.completed?(record) == @expected
      end
    end
  end

  describe "valid_statuses/0" do
    test "returns list of valid status atoms" do
      statuses = ParticipationRecord.valid_statuses()

      assert :registered in statuses
      assert :checked_in in statuses
      assert :checked_out in statuses
      assert :absent in statuses
      assert length(statuses) == 4
    end
  end

  describe "admin_correct/2" do
    setup do
      {:ok, record} =
        ParticipationRecord.new(%{
          id: "rec-1",
          session_id: "sess-1",
          child_id: "child-1"
        })

      %{record: record}
    end

    test "corrects registered → checked_in with check_in_at", %{record: record} do
      check_in_at = ~U[2026-03-13 09:00:00Z]

      assert {:ok, corrected} =
               ParticipationRecord.admin_correct(record, %{
                 status: :checked_in,
                 check_in_at: check_in_at
               })

      assert corrected.status == :checked_in
      assert corrected.check_in_at == check_in_at
    end

    test "corrects absent → checked_in (reverse transition)", %{record: record} do
      {:ok, absent} = ParticipationRecord.mark_absent(record)
      check_in_at = ~U[2026-03-13 09:05:00Z]

      assert {:ok, corrected} =
               ParticipationRecord.admin_correct(absent, %{
                 status: :checked_in,
                 check_in_at: check_in_at
               })

      assert corrected.status == :checked_in
    end

    test "corrects checked_out → checked_in (reverse transition)" do
      record = build_checked_out_record()

      assert {:ok, corrected} =
               ParticipationRecord.admin_correct(record, %{status: :checked_in})

      assert corrected.status == :checked_in
      assert corrected.check_out_at == nil
      assert corrected.check_out_by == nil
      assert corrected.check_out_notes == nil
    end

    test "corrects check_in_at time only (no status change)" do
      record = build_checked_in_record()
      new_time = ~U[2026-03-13 09:15:00Z]

      assert {:ok, corrected} =
               ParticipationRecord.admin_correct(record, %{check_in_at: new_time})

      assert corrected.check_in_at == new_time
      assert corrected.status == :checked_in
    end

    test "corrects check_out_at time only (no status change)" do
      record = build_checked_out_record()
      new_time = ~U[2026-03-13 11:30:00Z]

      assert {:ok, corrected} =
               ParticipationRecord.admin_correct(record, %{check_out_at: new_time})

      assert corrected.check_out_at == new_time
    end

    test "rejects check_out_at without check_in_at present" do
      {:ok, record} =
        ParticipationRecord.new(%{id: "r-1", session_id: "s-1", child_id: "c-1"})

      assert {:error, :check_out_requires_check_in} =
               ParticipationRecord.admin_correct(record, %{
                 status: :checked_out,
                 check_out_at: ~U[2026-03-13 10:00:00Z]
               })
    end

    test "rejects empty corrections (no changes)", %{record: record} do
      assert {:error, :no_changes} =
               ParticipationRecord.admin_correct(record, %{})
    end

    test "rejects invalid status atom", %{record: record} do
      assert {:error, :invalid_status} =
               ParticipationRecord.admin_correct(record, %{status: :invalid})
    end

    test "corrects checked_out → registered and clears all timing fields" do
      record = build_checked_out_record()

      assert {:ok, corrected} =
               ParticipationRecord.admin_correct(record, %{status: :registered})

      assert corrected.status == :registered
      assert corrected.check_in_at == nil
      assert corrected.check_in_by == nil
      assert corrected.check_in_notes == nil
      assert corrected.check_out_at == nil
      assert corrected.check_out_by == nil
      assert corrected.check_out_notes == nil
    end

    test "corrects checked_out → absent and clears all timing fields" do
      record = build_checked_out_record()

      assert {:ok, corrected} =
               ParticipationRecord.admin_correct(record, %{status: :absent})

      assert corrected.status == :absent
      assert corrected.check_in_at == nil
      assert corrected.check_in_by == nil
      assert corrected.check_in_notes == nil
      assert corrected.check_out_at == nil
      assert corrected.check_out_by == nil
      assert corrected.check_out_notes == nil
    end

    test "rejects check_out_at before check_in_at" do
      record = build_checked_in_record()

      assert {:error, :check_in_must_precede_check_out} =
               ParticipationRecord.admin_correct(record, %{
                 status: :checked_out,
                 check_in_at: ~U[2026-03-13 11:00:00Z],
                 check_out_at: ~U[2026-03-13 09:00:00Z]
               })
    end

    # -- helpers --

    defp build_checked_in_record do
      struct!(ParticipationRecord, %{
        id: "r-ci",
        session_id: "s-1",
        child_id: "c-1",
        status: :checked_in,
        check_in_at: ~U[2026-03-13 09:00:00Z],
        check_in_by: "provider-1",
        check_in_notes: "On time"
      })
    end

    defp build_checked_out_record do
      struct!(ParticipationRecord, %{
        id: "r-co",
        session_id: "s-1",
        child_id: "c-1",
        status: :checked_out,
        check_in_at: ~U[2026-03-13 09:00:00Z],
        check_in_by: "provider-1",
        check_in_notes: "On time",
        check_out_at: ~U[2026-03-13 10:00:00Z],
        check_out_by: "provider-1"
      })
    end
  end
end
