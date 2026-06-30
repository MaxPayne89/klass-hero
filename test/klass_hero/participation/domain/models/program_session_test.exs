defmodule KlassHero.Participation.ProgramSessionTest do
  @moduledoc """
  Tests for ProgramSession domain entity.

  Covers validation, status transitions, and predicate functions.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation.ProgramSession

  describe "new/1" do
    test "creates a valid session with all required fields" do
      attrs = %{
        id: Ecto.UUID.generate(),
        program_id: Ecto.UUID.generate(),
        session_date: ~D[2025-01-15],
        start_time: ~T[09:00:00],
        end_time: ~T[12:00:00]
      }

      assert {:ok, session} = ProgramSession.new(attrs)
      assert session.id == attrs.id
      assert session.program_id == attrs.program_id
      assert session.session_date == ~D[2025-01-15]
      assert session.start_time == ~T[09:00:00]
      assert session.end_time == ~T[12:00:00]
      assert session.status == :scheduled
      assert session.lock_version == 1
    end

    test "creates session with optional fields" do
      attrs = %{
        id: Ecto.UUID.generate(),
        program_id: Ecto.UUID.generate(),
        session_date: ~D[2025-01-15],
        start_time: ~T[09:00:00],
        end_time: ~T[12:00:00],
        notes: "Special equipment needed",
        location: "Room 101",
        max_capacity: 20
      }

      assert {:ok, session} = ProgramSession.new(attrs)
      assert session.notes == "Special equipment needed"
      assert session.location == "Room 101"
      assert session.max_capacity == 20
    end

    test "returns error when end_time is before start_time" do
      attrs = %{
        id: Ecto.UUID.generate(),
        program_id: Ecto.UUID.generate(),
        session_date: ~D[2025-01-15],
        start_time: ~T[14:00:00],
        end_time: ~T[09:00:00]
      }

      assert {:error, :invalid_time_range} = ProgramSession.new(attrs)
    end

    test "returns error when end_time equals start_time" do
      attrs = %{
        id: Ecto.UUID.generate(),
        program_id: Ecto.UUID.generate(),
        session_date: ~D[2025-01-15],
        start_time: ~T[09:00:00],
        end_time: ~T[09:00:00]
      }

      assert {:error, :invalid_time_range} = ProgramSession.new(attrs)
    end

    test "returns error when required fields are missing" do
      # Missing id
      attrs = %{
        program_id: Ecto.UUID.generate(),
        session_date: ~D[2025-01-15],
        start_time: ~T[09:00:00],
        end_time: ~T[12:00:00]
      }

      assert {:error, :missing_required_fields} = ProgramSession.new(attrs)
    end

    test "returns error when program_id is missing" do
      attrs = %{
        id: Ecto.UUID.generate(),
        session_date: ~D[2025-01-15],
        start_time: ~T[09:00:00],
        end_time: ~T[12:00:00]
      }

      assert {:error, :missing_required_fields} = ProgramSession.new(attrs)
    end

    test "returns error when session_date is missing" do
      attrs = %{
        id: Ecto.UUID.generate(),
        program_id: Ecto.UUID.generate(),
        start_time: ~T[09:00:00],
        end_time: ~T[12:00:00]
      }

      assert {:error, :missing_required_fields} = ProgramSession.new(attrs)
    end

    test "returns error when start_time is missing" do
      attrs = %{
        id: Ecto.UUID.generate(),
        program_id: Ecto.UUID.generate(),
        session_date: ~D[2025-01-15],
        end_time: ~T[12:00:00]
      }

      assert {:error, :missing_required_fields} = ProgramSession.new(attrs)
    end

    test "returns error when end_time is missing" do
      attrs = %{
        id: Ecto.UUID.generate(),
        program_id: Ecto.UUID.generate(),
        session_date: ~D[2025-01-15],
        start_time: ~T[09:00:00]
      }

      assert {:error, :missing_required_fields} = ProgramSession.new(attrs)
    end
  end

  describe "start/1" do
    test "transitions :scheduled session to :in_progress" do
      session = build(:program_session, status: :scheduled)

      assert {:ok, started} = ProgramSession.start(session)
      assert started.status == :in_progress
    end

    test "returns error when starting :in_progress session" do
      session = build(:program_session, status: :in_progress)

      assert {:error, :invalid_status_transition} = ProgramSession.start(session)
    end

    test "returns error when starting :completed session" do
      session = build(:program_session, status: :completed)

      assert {:error, :invalid_status_transition} = ProgramSession.start(session)
    end

    test "returns error when starting :cancelled session" do
      session = build(:program_session, status: :cancelled)

      assert {:error, :invalid_status_transition} = ProgramSession.start(session)
    end
  end

  describe "complete/1" do
    test "transitions :in_progress session to :completed" do
      session = build(:program_session, status: :in_progress)

      assert {:ok, completed} = ProgramSession.complete(session)
      assert completed.status == :completed
    end

    test "returns error when completing :scheduled session" do
      session = build(:program_session, status: :scheduled)

      assert {:error, :invalid_status_transition} = ProgramSession.complete(session)
    end

    test "returns error when completing :completed session" do
      session = build(:program_session, status: :completed)

      assert {:error, :invalid_status_transition} = ProgramSession.complete(session)
    end

    test "returns error when completing :cancelled session" do
      session = build(:program_session, status: :cancelled)

      assert {:error, :invalid_status_transition} = ProgramSession.complete(session)
    end
  end

  describe "cancel/1" do
    test "transitions :scheduled session to :cancelled" do
      session = build(:program_session, status: :scheduled)

      assert {:ok, cancelled} = ProgramSession.cancel(session)
      assert cancelled.status == :cancelled
    end

    test "returns error when cancelling :in_progress session" do
      session = build(:program_session, status: :in_progress)

      assert {:error, :invalid_status_transition} = ProgramSession.cancel(session)
    end

    test "returns error when cancelling :completed session" do
      session = build(:program_session, status: :completed)

      assert {:error, :invalid_status_transition} = ProgramSession.cancel(session)
    end

    test "returns error when cancelling :cancelled session" do
      session = build(:program_session, status: :cancelled)

      assert {:error, :invalid_status_transition} = ProgramSession.cancel(session)
    end
  end

  describe "can_accept_participants?/1" do
    test "returns true for :scheduled session" do
      session = build(:program_session, status: :scheduled)
      assert ProgramSession.can_accept_participants?(session)
    end

    test "returns true for :in_progress session" do
      session = build(:program_session, status: :in_progress)
      assert ProgramSession.can_accept_participants?(session)
    end

    test "returns false for :completed session" do
      session = build(:program_session, status: :completed)
      refute ProgramSession.can_accept_participants?(session)
    end

    test "returns false for :cancelled session" do
      session = build(:program_session, status: :cancelled)
      refute ProgramSession.can_accept_participants?(session)
    end
  end

  describe "in_progress?/1" do
    test "returns true for :in_progress session" do
      session = build(:program_session, status: :in_progress)
      assert ProgramSession.in_progress?(session)
    end

    test "returns false for :scheduled session" do
      session = build(:program_session, status: :scheduled)
      refute ProgramSession.in_progress?(session)
    end

    test "returns false for :completed session" do
      session = build(:program_session, status: :completed)
      refute ProgramSession.in_progress?(session)
    end

    test "returns false for :cancelled session" do
      session = build(:program_session, status: :cancelled)
      refute ProgramSession.in_progress?(session)
    end
  end

  describe "duration_minutes/1" do
    test "calculates duration correctly" do
      session = build(:program_session, start_time: ~T[09:00:00], end_time: ~T[12:00:00])
      assert ProgramSession.duration_minutes(session) == 180
    end

    test "calculates short duration correctly" do
      session = build(:program_session, start_time: ~T[10:00:00], end_time: ~T[10:30:00])
      assert ProgramSession.duration_minutes(session) == 30
    end

    test "calculates exact hour duration" do
      session = build(:program_session, start_time: ~T[09:00:00], end_time: ~T[10:00:00])
      assert ProgramSession.duration_minutes(session) == 60
    end
  end

  describe "valid_statuses/0" do
    test "returns list of valid status atoms" do
      statuses = ProgramSession.valid_statuses()

      assert :scheduled in statuses
      assert :in_progress in statuses
      assert :completed in statuses
      assert :cancelled in statuses
      assert length(statuses) == 4
    end
  end
end
