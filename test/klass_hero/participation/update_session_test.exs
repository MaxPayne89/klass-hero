defmodule KlassHero.Participation.UpdateSessionTest do
  @moduledoc """
  Editing an existing session's schedule and details (#1074).

  Until this command there was no way to correct a session at all: the facade had
  `create`, `start` and `complete`, and `update_changeset/2` could not cast a date
  or a time. So a provider who typed the wrong hour had a wrong session forever.

  Two rules carry most of the weight here. Rescheduling stops at `:scheduled`,
  because attendance records are keyed to the session and moving a completed one
  rewrites history its roster cannot follow. And staff are refused, matching
  creation: assignment is permission to *run* a session, not to move it.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Participation
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.ProviderFixtures

  describe "update_session/3" do
    test "reschedules a scheduled session" do
      %{scope: scope, session: session} = provider_with_session()

      assert {:ok, %ProgramSession{} = updated} =
               Participation.update_session(scope, session.id, %{
                 session_date: ~D[2026-09-09],
                 start_time: ~T[10:00:00],
                 end_time: ~T[11:30:00]
               })

      assert updated.session_date == ~D[2026-09-09]
      assert updated.start_time == ~T[10:00:00]
      assert updated.end_time == ~T[11:30:00]
    end

    test "edits the details without touching the schedule" do
      %{scope: scope, session: session} = provider_with_session()

      assert {:ok, updated} =
               Participation.update_session(scope, session.id, %{
                 location: "Gym B",
                 notes: "Bring water",
                 max_capacity: 12
               })

      assert updated.location == "Gym B"
      assert updated.notes == "Bring water"
      assert updated.max_capacity == 12
      assert updated.session_date == session.session_date
    end

    test "returns :not_found for an unknown session" do
      %{scope: scope} = provider_with_session()

      assert {:error, :not_found} =
               Participation.update_session(scope, Ecto.UUID.generate(), %{location: "Gym B"})
    end

    test "refuses a provider who does not own the program" do
      %{session: session} = provider_with_session()
      foreign = %Scope{provider: %ProviderProfile{id: Ecto.UUID.generate()}}

      assert {:error, :unauthorized} =
               Participation.update_session(foreign, session.id, %{location: "Gym B"})
    end

    test "refuses a staff member assigned to the program" do
      %{provider: provider, program: program, session: session} = provider_with_session()
      staff = ProviderFixtures.staff_member_fixture(%{provider_id: provider.id})

      ProviderFixtures.program_assignment_fixture(%{
        provider_id: provider.id,
        staff_member_id: staff.id,
        program_id: program.id
      })

      scope = %Scope{user: AccountsFixtures.unconfirmed_user_fixture(), staff_member: staff}

      assert {:error, :unauthorized} =
               Participation.update_session(scope, session.id, %{location: "Gym B"})
    end

    # Assumption 1 in the plan: the schedule freezes once the session has started,
    # the details do not.
    for status <- [:in_progress, :completed, :cancelled] do
      test "refuses a schedule change on a #{status} session" do
        %{scope: scope, session: session} = provider_with_session(status: unquote(status))

        assert {:error, :session_started} =
                 Participation.update_session(scope, session.id, %{session_date: ~D[2026-09-09]})
      end

      test "still allows a detail edit on a #{status} session" do
        %{scope: scope, session: session} = provider_with_session(status: unquote(status))

        assert {:ok, updated} = Participation.update_session(scope, session.id, %{location: "Gym B"})
        assert updated.location == "Gym B"
      end
    end

    # A no-op reschedule is not a reschedule: re-submitting the form unchanged
    # must not be refused just because the keys are present.
    test "allows a submitted-but-unchanged schedule on a completed session" do
      %{scope: scope, session: session} = provider_with_session(status: :completed)

      assert {:ok, _updated} =
               Participation.update_session(scope, session.id, %{
                 session_date: session.session_date,
                 start_time: session.start_time,
                 location: "Gym B"
               })
    end

    test "returns an error tuple when the new slot is already taken" do
      %{scope: scope, program: program, session: session} = provider_with_session()

      insert(:program_session_schema,
        program_id: program.id,
        session_date: ~D[2026-09-09],
        start_time: ~T[10:00:00]
      )

      # End time moves with the start: leaving it at the stored 10:00 would invert
      # the range and trip that validation first, never reaching the constraint.
      assert {:error, :duplicate_session} =
               Participation.update_session(scope, session.id, %{
                 session_date: ~D[2026-09-09],
                 start_time: ~T[10:00:00],
                 end_time: ~T[11:30:00]
               })
    end

    # Guards the asymmetry `SessionFormHandlers.clear_blank_capacity/2` relies on:
    # a submitted-blank capacity clears, an omitted one must not. Today only one
    # surface calls it and that surface always renders the input, so this pins the
    # contract for the next one.
    test "leaves max_capacity alone when the attr is absent" do
      %{scope: scope, session: session} = provider_with_session()
      {:ok, _} = Participation.update_session(scope, session.id, %{max_capacity: 25})

      assert {:ok, updated} = Participation.update_session(scope, session.id, %{location: "Gym B"})

      assert updated.max_capacity == 25
    end

    test "clears max_capacity when the attr is present and nil" do
      %{scope: scope, session: session} = provider_with_session()
      {:ok, _} = Participation.update_session(scope, session.id, %{max_capacity: 25})

      assert {:ok, updated} = Participation.update_session(scope, session.id, %{max_capacity: nil})

      assert is_nil(updated.max_capacity)
    end

    test "rejects an end time before the start time" do
      %{scope: scope, session: session} = provider_with_session()

      assert {:error, :invalid_time_range} =
               Participation.update_session(scope, session.id, %{
                 start_time: ~T[14:00:00],
                 end_time: ~T[09:00:00]
               })
    end
  end

  defp provider_with_session(opts \\ []) do
    provider = ProviderFixtures.provider_profile_fixture()
    program = insert(:program_schema, provider_id: provider.id)

    session =
      insert(:program_session_schema,
        program_id: program.id,
        session_date: ~D[2026-09-01],
        start_time: ~T[09:00:00],
        end_time: ~T[10:00:00],
        status: Keyword.get(opts, :status, :scheduled)
      )

    %{
      provider: provider,
      program: program,
      session: session,
      scope: %Scope{provider: provider}
    }
  end
end
