defmodule KlassHero.Participation.CorrectAttendanceTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Participation
  alias KlassHero.ProviderFixtures

  describe "correct_attendance/3" do
    setup do
      user = AccountsFixtures.unconfirmed_user_fixture()

      # The session's program must have a real owner: the correction rules follow
      # the role the context derives from the caller's scope (#1353), so provider
      # ownership and staff assignment have to actually exist to be found.
      provider = ProviderFixtures.provider_profile_fixture()
      program = insert(:program_schema, provider_id: provider.id)
      session = insert(:program_session_schema, program_id: program.id, status: "in_progress")

      staff = ProviderFixtures.staff_member_fixture(%{provider_id: provider.id})

      ProviderFixtures.program_assignment_fixture(%{
        provider_id: provider.id,
        staff_member_id: staff.id,
        program_id: program.id
      })

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

      %{
        record: record,
        session: session,
        user: user,
        admin_scope: AccountsFixtures.admin_scope_fixture(),
        provider_scope: %Scope{user: user, provider: provider},
        staff_scope: %Scope{user: user, staff_member: staff}
      }
    end

    test "corrects status with required reason", %{record: record, admin_scope: scope} do
      assert {:ok, corrected} =
               Participation.correct_attendance(scope, record.id, %{
                 status: :checked_out,
                 check_out_at: ~U[2026-03-13 10:30:00Z],
                 reason: "Provider forgot to check out"
               })

      assert corrected.status == :checked_out
      assert corrected.check_out_at == ~U[2026-03-13 10:30:00Z]
      assert corrected.check_out_notes =~ "[Admin correction]"
      assert corrected.check_out_notes =~ "Provider forgot to check out"
    end

    test "corrects check_in_at time with reason appended to existing notes", %{
      record: record,
      admin_scope: scope
    } do
      new_time = ~U[2026-03-13 09:15:00Z]

      assert {:ok, corrected} =
               Participation.correct_attendance(scope, record.id, %{
                 check_in_at: new_time,
                 reason: "Wrong check-in time recorded"
               })

      assert corrected.check_in_at == new_time
      assert corrected.check_in_notes =~ "[Admin correction]"
    end

    test "appends correction reason to pre-existing notes with separator", %{
      session: session,
      user: user,
      admin_scope: scope
    } do
      record_with_notes = record_with_check_in_notes(session, user, "Arrived on time")

      assert {:ok, corrected} =
               Participation.correct_attendance(scope, record_with_notes.id, %{
                 check_in_at: ~U[2026-03-13 09:30:00Z],
                 reason: "Actually arrived late"
               })

      assert corrected.check_in_notes =~ "Arrived on time"
      assert corrected.check_in_notes =~ " | "
      assert corrected.check_in_notes =~ "[Admin correction] Actually arrived late"
    end

    test "rejects correction without reason", %{record: record, admin_scope: scope} do
      assert {:error, :reason_required} =
               Participation.correct_attendance(scope, record.id, %{
                 status: :checked_out,
                 check_out_at: ~U[2026-03-13 10:30:00Z]
               })
    end

    test "rejects correction with blank reason", %{record: record, admin_scope: scope} do
      assert {:error, :reason_required} =
               Participation.correct_attendance(scope, record.id, %{status: :absent, reason: "   "})
    end

    test "rejects correction with no changes", %{record: record, admin_scope: scope} do
      assert {:error, :no_changes} =
               Participation.correct_attendance(scope, record.id, %{reason: "Testing"})
    end

    test "returns not_found for invalid record_id", %{admin_scope: scope} do
      assert {:error, :not_found} =
               Participation.correct_attendance(scope, Ecto.UUID.generate(), %{
                 status: :absent,
                 reason: "Mistake"
               })
    end

    test "status-only correction appends reason to check_in_notes", %{
      record: record,
      admin_scope: scope
    } do
      assert {:ok, corrected} =
               Participation.correct_attendance(scope, record.id, %{
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
      user: user,
      admin_scope: scope
    } do
      record_with_empty_notes = record_with_check_in_notes(session, user, "")

      assert {:ok, corrected} =
               Participation.correct_attendance(scope, record_with_empty_notes.id, %{
                 check_in_at: ~U[2026-03-13 09:30:00Z],
                 reason: "Wrong time recorded"
               })

      assert corrected.check_in_notes == "[Admin correction] Wrong time recorded"
      refute corrected.check_in_notes =~ " | "
    end

    # Provider and staff correct their own roster without a reason. Each reaches
    # that rule down a different authorization path — program ownership versus a
    # program staff assignment — so both are exercised rather than assumed alike.
    for role <- [:provider, :staff] do
      @scope_key :"#{role}_scope"

      test "#{role}: patches check_in_notes without requiring a reason", context do
        scope = Map.fetch!(context, @scope_key)

        assert {:ok, corrected} =
                 Participation.correct_attendance(scope, context.record.id, %{
                   check_in_notes: "Updated by #{unquote(role)}"
                 })

        assert corrected.check_in_notes == "Updated by #{unquote(role)}"
        refute corrected.check_in_notes =~ "[Admin correction]"
      end

      test "#{role}: records a retroactive check-out time and notes", context do
        scope = Map.fetch!(context, @scope_key)

        assert {:ok, corrected} =
                 Participation.correct_attendance(scope, context.record.id, %{
                   status: :checked_out,
                   check_out_at: ~U[2026-03-13 10:30:00Z],
                   check_out_notes: "Picked up by mom"
                 })

        assert corrected.status == :checked_out
        assert corrected.check_out_at == ~U[2026-03-13 10:30:00Z]
        assert corrected.check_out_notes == "Picked up by mom"
        refute (corrected.check_out_notes || "") =~ "[Admin correction]"
      end

      test "#{role}: rejects edits with no actual changes", context do
        scope = Map.fetch!(context, @scope_key)

        assert {:error, :no_changes} =
                 Participation.correct_attendance(scope, context.record.id, %{})
      end

      test "#{role}: treats notes-equal-to-existing as no_changes", context do
        scope = Map.fetch!(context, @scope_key)

        assert {:error, :no_changes} =
                 Participation.correct_attendance(scope, context.record.id, %{
                   check_in_notes: context.record.check_in_notes
                 })
      end
    end

    test "refuses an actor with no persona and no admin flag", %{record: record, user: user} do
      assert {:error, :unauthorized} =
               Participation.correct_attendance(%Scope{user: user}, record.id, %{
                 check_in_notes: "Not mine to touch"
               })
    end

    test "refuses a provider who does not own the session's program", %{record: record, user: user} do
      other_provider = ProviderFixtures.provider_profile_fixture()

      assert {:error, :unauthorized} =
               Participation.correct_attendance(
                 %Scope{user: user, provider: other_provider},
                 record.id,
                 %{check_in_notes: "Not mine to touch"}
               )
    end

    defp record_with_check_in_notes(session, user, notes) do
      {child, parent} = insert_child_with_guardian()

      insert(:participation_record_schema,
        session_id: session.id,
        child_id: child.id,
        parent_id: parent.id,
        status: :checked_in,
        check_in_at: ~U[2026-03-13 09:00:00Z],
        check_in_by: user.id,
        check_in_notes: notes
      )
    end
  end
end
