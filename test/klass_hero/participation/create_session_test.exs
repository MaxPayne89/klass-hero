defmodule KlassHero.Participation.CreateSessionTest do
  @moduledoc """
  Integration tests for CreateSession use case.

  Tests session creation with domain validation and persistence.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation.ProgramSession

  describe "execute/1" do
    test "successfully creates a session with valid attributes" do
      program = insert(:program_schema)

      assert {:ok, session} =
               KlassHero.Participation.create_session(%{
                 program_id: program.id,
                 session_date: ~D[2025-02-15],
                 start_time: ~T[09:00:00],
                 end_time: ~T[12:00:00],
                 max_capacity: 20,
                 notes: "Morning session"
               })

      assert %ProgramSession{} = session
      assert session.program_id == program.id
      assert session.session_date == ~D[2025-02-15]
      assert session.start_time == ~T[09:00:00]
      assert session.end_time == ~T[12:00:00]
      assert session.max_capacity == 20
      assert session.status == :scheduled
      assert session.notes == "Morning session"
    end

    test "creates session with default nil notes when not provided" do
      program = insert(:program_schema)

      assert {:ok, session} =
               KlassHero.Participation.create_session(%{
                 program_id: program.id,
                 session_date: ~D[2025-02-15],
                 start_time: ~T[09:00:00],
                 end_time: ~T[12:00:00],
                 max_capacity: 20
               })

      assert session.notes == nil
    end

    test "creates session with location" do
      program = insert(:program_schema)

      assert {:ok, session} =
               KlassHero.Participation.create_session(%{
                 program_id: program.id,
                 session_date: ~D[2025-02-15],
                 start_time: ~T[09:00:00],
                 end_time: ~T[12:00:00],
                 max_capacity: 20,
                 location: "Room 101"
               })

      assert session.location == "Room 101"
    end

    test "returns error when end_time is before start_time" do
      program = insert(:program_schema)

      assert {:error, reason} =
               KlassHero.Participation.create_session(%{
                 program_id: program.id,
                 session_date: ~D[2025-02-15],
                 start_time: ~T[14:00:00],
                 end_time: ~T[09:00:00],
                 max_capacity: 20
               })

      assert reason != nil
    end

    test "allows sessions with different dates for same program" do
      program = insert(:program_schema)

      assert {:ok, _session1} =
               KlassHero.Participation.create_session(%{
                 program_id: program.id,
                 session_date: ~D[2025-02-15],
                 start_time: ~T[09:00:00],
                 end_time: ~T[12:00:00],
                 max_capacity: 20
               })

      assert {:ok, session2} =
               KlassHero.Participation.create_session(%{
                 program_id: program.id,
                 session_date: ~D[2025-02-16],
                 start_time: ~T[09:00:00],
                 end_time: ~T[12:00:00],
                 max_capacity: 20
               })

      assert session2.session_date == ~D[2025-02-16]
    end

    test "allows sessions with different start times on same date" do
      program = insert(:program_schema)

      assert {:ok, _session1} =
               KlassHero.Participation.create_session(%{
                 program_id: program.id,
                 session_date: ~D[2025-02-15],
                 start_time: ~T[09:00:00],
                 end_time: ~T[12:00:00],
                 max_capacity: 20
               })

      assert {:ok, session2} =
               KlassHero.Participation.create_session(%{
                 program_id: program.id,
                 session_date: ~D[2025-02-15],
                 start_time: ~T[14:00:00],
                 end_time: ~T[17:00:00],
                 max_capacity: 20
               })

      assert session2.start_time == ~T[14:00:00]
    end
  end
end
