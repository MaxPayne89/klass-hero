defmodule KlassHero.Participation.CorrectAttendanceTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation

  describe "correct_attendance/1" do
    setup do
      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()
      _provider = insert(:provider_profile_schema)
      session = insert(:program_session_schema, status: "in_progress")

      {child, parent} = insert_child_with_guardian()

      record =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          parent_id: parent.id,
          status: :checked_in,
          check_in_at: ~U[2026-03-13 09:00:00Z],
          check_in_by: user.id
        )

      %{record: record, session: session, user: user}
    end

    test "corrects status with required reason", %{record: record} do
      assert {:ok, corrected} =
               Participation.correct_attendance(%{
                 record_id: record.id,
                 status: :checked_out,
                 check_out_at: ~U[2026-03-13 10:30:00Z],
                 reason: "Provider forgot to check out"
               })

      assert corrected.status == :checked_out
      assert corrected.check_out_at == ~U[2026-03-13 10:30:00Z]
      assert corrected.check_out_notes =~ "[Admin correction]"
      assert corrected.check_out_notes =~ "Provider forgot to check out"
    end

    test "corrects check_in_at time with reason appended to existing notes", %{record: record} do
      new_time = ~U[2026-03-13 09:15:00Z]

      assert {:ok, corrected} =
               Participation.correct_attendance(%{
                 record_id: record.id,
                 check_in_at: new_time,
                 reason: "Wrong check-in time recorded"
               })

      assert corrected.check_in_at == new_time
      assert corrected.check_in_notes =~ "[Admin correction]"
    end

    test "appends correction reason to pre-existing notes with separator", %{
      session: session,
      user: user
    } do
      {child, parent} = insert_child_with_guardian()

      record_with_notes =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          parent_id: parent.id,
          status: :checked_in,
          check_in_at: ~U[2026-03-13 09:00:00Z],
          check_in_by: user.id,
          check_in_notes: "Arrived on time"
        )

      assert {:ok, corrected} =
               Participation.correct_attendance(%{
                 record_id: record_with_notes.id,
                 check_in_at: ~U[2026-03-13 09:30:00Z],
                 reason: "Actually arrived late"
               })

      assert corrected.check_in_notes =~ "Arrived on time"
      assert corrected.check_in_notes =~ " | "
      assert corrected.check_in_notes =~ "[Admin correction] Actually arrived late"
    end

    test "rejects correction without reason", %{record: record} do
      assert {:error, :reason_required} =
               Participation.correct_attendance(%{
                 record_id: record.id,
                 status: :checked_out,
                 check_out_at: ~U[2026-03-13 10:30:00Z]
               })
    end

    test "rejects correction with blank reason", %{record: record} do
      assert {:error, :reason_required} =
               Participation.correct_attendance(%{
                 record_id: record.id,
                 status: :absent,
                 reason: "   "
               })
    end

    test "rejects correction with no changes", %{record: record} do
      assert {:error, :no_changes} =
               Participation.correct_attendance(%{
                 record_id: record.id,
                 reason: "Testing"
               })
    end

    test "returns not_found for invalid record_id" do
      assert {:error, :not_found} =
               Participation.correct_attendance(%{
                 record_id: Ecto.UUID.generate(),
                 status: :absent,
                 reason: "Mistake"
               })
    end

    test "status-only correction appends reason to check_in_notes", %{record: record} do
      assert {:ok, corrected} =
               Participation.correct_attendance(%{
                 record_id: record.id,
                 status: :absent,
                 reason: "Child did not attend"
               })

      assert corrected.status == :absent
      assert corrected.check_in_notes =~ "[Admin correction]"
      assert corrected.check_in_notes =~ "Child did not attend"
      assert is_nil(corrected.check_out_notes)
    end

    test "correction reason stands alone when existing notes field is empty string", %{
      session: session,
      user: user
    } do
      {child, parent} = insert_child_with_guardian()

      record_with_empty_notes =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          parent_id: parent.id,
          status: :checked_in,
          check_in_at: ~U[2026-03-13 09:00:00Z],
          check_in_by: user.id,
          check_in_notes: ""
        )

      assert {:ok, corrected} =
               Participation.correct_attendance(%{
                 record_id: record_with_empty_notes.id,
                 check_in_at: ~U[2026-03-13 09:30:00Z],
                 reason: "Wrong time recorded"
               })

      assert corrected.check_in_notes == "[Admin correction] Wrong time recorded"
      refute corrected.check_in_notes =~ " | "
    end

    for role <- [:provider, :staff] do
      test "actor_role #{role}: patches check_in_notes without requiring a reason", %{
        record: record
      } do
        assert {:ok, corrected} =
                 Participation.correct_attendance(%{
                   record_id: record.id,
                   actor_role: unquote(role),
                   check_in_notes: "Updated by #{unquote(role)}"
                 })

        assert corrected.check_in_notes == "Updated by #{unquote(role)}"
        refute corrected.check_in_notes =~ "[Admin correction]"
      end

      test "actor_role #{role}: records a retroactive check-out time and notes", %{
        record: record
      } do
        assert {:ok, corrected} =
                 Participation.correct_attendance(%{
                   record_id: record.id,
                   actor_role: unquote(role),
                   status: :checked_out,
                   check_out_at: ~U[2026-03-13 10:30:00Z],
                   check_out_notes: "Picked up by mom"
                 })

        assert corrected.status == :checked_out
        assert corrected.check_out_at == ~U[2026-03-13 10:30:00Z]
        assert corrected.check_out_notes == "Picked up by mom"
        refute (corrected.check_out_notes || "") =~ "[Admin correction]"
      end

      test "actor_role #{role}: rejects edits with no actual changes", %{record: record} do
        assert {:error, :no_changes} =
                 Participation.correct_attendance(%{
                   record_id: record.id,
                   actor_role: unquote(role)
                 })
      end

      test "actor_role #{role}: treats notes-equal-to-existing as no_changes", %{
        record: record
      } do
        assert {:error, :no_changes} =
                 Participation.correct_attendance(%{
                   record_id: record.id,
                   actor_role: unquote(role),
                   check_in_notes: record.check_in_notes
                 })
      end
    end
  end
end
