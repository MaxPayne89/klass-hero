defmodule KlassHero.Participation.BackfillRosterForEnrollmentTest do
  @moduledoc """
  A child who enrolls *after* a Session already exists must still appear on that
  Session's Roster.

  `CONTEXT.md` states the invariant directly: an Enrollment "feeds the Roster of
  every Session in that Program". Today the only seeding trigger is
  `session_created`, so the Roster is a snapshot frozen at Session-creation time
  and a later Enrollment reaches no Roster at all.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation

  describe "backfill_roster_for_enrollment/2" do
    test "puts a late-enrolling child on an existing future Session's Roster" do
      program = insert(:program_schema)
      {child, _parent} = insert_child_with_guardian()

      {:ok, session} =
        Participation.create_session(%{
          program_id: program.id,
          session_date: Date.add(Date.utc_today(), 7),
          start_time: ~T[15:00:00],
          end_time: ~T[17:00:00],
          max_capacity: 20
        })

      # The Session's Roster is seeded at creation, when nobody is enrolled yet.
      assert {:ok, %{roster: []}} = Participation.get_session_with_roster(session.id)

      insert(:enrollment_schema, program_id: program.id, child_id: child.id, status: :confirmed)

      assert :ok = Participation.backfill_roster_for_enrollment(child.id, program.id)

      assert {:ok, %{roster: [entry]}} = Participation.get_session_with_roster(session.id)
      assert entry.record.child_id == child.id
      assert entry.record.status == :registered
    end

    test "is idempotent — re-running does not duplicate the Roster entry" do
      program = insert(:program_schema)
      {child, _parent} = insert_child_with_guardian()

      {:ok, session} =
        Participation.create_session(%{
          program_id: program.id,
          session_date: Date.add(Date.utc_today(), 7),
          start_time: ~T[15:00:00],
          end_time: ~T[17:00:00],
          max_capacity: 20
        })

      insert(:enrollment_schema, program_id: program.id, child_id: child.id, status: :confirmed)

      assert :ok = Participation.backfill_roster_for_enrollment(child.id, program.id)
      assert :ok = Participation.backfill_roster_for_enrollment(child.id, program.id)

      assert {:ok, %{roster: [_only_one]}} = Participation.get_session_with_roster(session.id)
    end

    test "leaves past Sessions alone — attendance history is not rewritten" do
      program = insert(:program_schema)
      {child, _parent} = insert_child_with_guardian()

      {:ok, past_session} =
        Participation.create_session(%{
          program_id: program.id,
          session_date: Date.add(Date.utc_today(), -7),
          start_time: ~T[15:00:00],
          end_time: ~T[17:00:00],
          max_capacity: 20
        })

      insert(:enrollment_schema, program_id: program.id, child_id: child.id, status: :confirmed)

      assert :ok = Participation.backfill_roster_for_enrollment(child.id, program.id)

      assert {:ok, %{roster: []}} = Participation.get_session_with_roster(past_session.id)
    end
  end
end
