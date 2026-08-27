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

  describe "occupancy/2" do
    # {Session Capacity, roster count, expected}. The 5/6 row is the shape live in
    # production: four completed sessions hold six children on a capacity of five.
    @occupancy_cases [
      {nil, 0, :uncapped},
      {nil, 99, :uncapped},
      {5, 4, :within},
      {5, 5, :full},
      {5, 6, :over},
      {12, 0, :within}
    ]

    # `get_session_with_roster_enriched/1` hands the card a `Map.from_struct`'d
    # session so presentation fields can be merged onto it, so the roster detail
    # pages ask this question about a plain map, never a `%ProgramSession{}`.
    test "answers for the enriched plain map the roster detail pages carry" do
      enriched =
        :program_session
        |> build(max_capacity: 5)
        |> Map.from_struct()
        |> Map.put(:program_name, "After-School Club")

      assert ProgramSession.occupancy(enriched, 6) == :over
    end

    for {capacity, count, expected} <- @occupancy_cases do
      test "capacity #{inspect(capacity)} with #{count} on the roster is #{inspect(expected)}" do
        session = build(:program_session, max_capacity: unquote(capacity))

        assert ProgramSession.occupancy(session, unquote(count)) == unquote(expected),
               "expected a roster of #{unquote(count)} against a Session Capacity of " <>
                 "#{inspect(unquote(capacity))} to read #{inspect(unquote(expected))}"
      end
    end
  end

  # Until #1074 this changeset cast only the optional fields plus :status, so
  # rescheduling was impossible by construction — there was no command to do it
  # and no changeset that would have accepted it.
  describe "update_changeset/2" do
    test "casts the schedule fields" do
      changeset =
        ProgramSession.update_changeset(%ProgramSession{}, %{
          session_date: ~D[2026-09-02],
          start_time: ~T[10:00:00],
          end_time: ~T[11:30:00]
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :session_date) == ~D[2026-09-02]
      assert Ecto.Changeset.get_change(changeset, :start_time) == ~T[10:00:00]
      assert Ecto.Changeset.get_change(changeset, :end_time) == ~T[11:30:00]
    end

    test "rejects an end time at or before the start time" do
      session = %ProgramSession{start_time: ~T[09:00:00], end_time: ~T[10:00:00]}

      changeset = ProgramSession.update_changeset(session, %{end_time: ~T[08:00:00]})

      refute changeset.valid?
      assert %{end_time: ["must be after start time"]} = errors_on(changeset)
    end

    # The half a partial edit gets wrong: changing only the start time has to be
    # compared against the *stored* end time, not against nothing.
    test "compares a changed start time against the session's existing end time" do
      session = %ProgramSession{start_time: ~T[09:00:00], end_time: ~T[10:00:00]}

      changeset = ProgramSession.update_changeset(session, %{start_time: ~T[11:00:00]})

      refute changeset.valid?
    end

    test "still rejects a non-positive capacity" do
      changeset = ProgramSession.update_changeset(%ProgramSession{}, %{max_capacity: 0})

      refute changeset.valid?
    end

    # A reschedule can land on a slot another session already holds. Without the
    # constraint declared here that surfaces as an Ecto.ConstraintError — a 500,
    # not a form error the provider can act on.
    test "declares the slot uniqueness constraint so a collision is an error tuple" do
      program = insert(:program_schema)

      insert(:program_session_schema,
        program_id: program.id,
        session_date: ~D[2026-09-03],
        start_time: ~T[09:00:00]
      )

      clash =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: ~D[2026-09-04],
          start_time: ~T[09:00:00]
        )

      assert {:error, changeset} =
               clash
               |> ProgramSession.update_changeset(%{session_date: ~D[2026-09-03]})
               |> Repo.update()

      assert %{program_id: ["session already exists at this time"]} = errors_on(changeset)
    end
  end
end
