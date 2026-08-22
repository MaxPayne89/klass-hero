defmodule KlassHero.Participation.CompleteSessionTest do
  @moduledoc """
  Integration tests for CompleteSession use case.

  Tests completing an in_progress session and transitioning it to completed.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Participation
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.ProviderFixtures

  describe "execute/1" do
    test "successfully completes an in_progress session" do
      session_schema = insert(:program_session_schema, status: :in_progress)

      assert {:ok, session} = KlassHero.Participation.complete_session(admin_scope(), session_schema.id)
      assert %ProgramSession{} = session
      assert session.id == session_schema.id
      assert session.status == :completed
    end

    test "returns error when session not found" do
      non_existent_id = Ecto.UUID.generate()

      assert {:error, :not_found} = KlassHero.Participation.complete_session(admin_scope(), non_existent_id)
    end

    test "returns error when completing a scheduled session" do
      session_schema = insert(:program_session_schema, status: :scheduled)

      assert {:error, :invalid_status_transition} =
               KlassHero.Participation.complete_session(admin_scope(), session_schema.id)
    end

    test "returns error when completing a completed session" do
      session_schema = insert(:program_session_schema, status: :completed)

      assert {:error, :invalid_status_transition} =
               KlassHero.Participation.complete_session(admin_scope(), session_schema.id)
    end

    test "returns error when completing a cancelled session" do
      session_schema = insert(:program_session_schema, status: :cancelled)

      assert {:error, :invalid_status_transition} =
               KlassHero.Participation.complete_session(admin_scope(), session_schema.id)
    end

    test "persists status change to database" do
      session_schema = insert(:program_session_schema, status: :in_progress)

      {:ok, completed_session} = KlassHero.Participation.complete_session(admin_scope(), session_schema.id)

      reloaded =
        KlassHero.Repo.get(
          ProgramSession,
          session_schema.id
        )

      assert reloaded.status == :completed
      assert completed_session.status == :completed
    end

    test "persists registered participants as absent in the database" do
      session_schema = insert(:program_session_schema, status: :in_progress)
      child = insert(:child_schema)

      record =
        insert(:participation_record_schema,
          session_id: session_schema.id,
          child_id: child.id,
          status: :registered
        )

      assert {:ok, _session} = KlassHero.Participation.complete_session(admin_scope(), session_schema.id)

      reloaded = KlassHero.Repo.get(ParticipationRecord, record.id)
      assert reloaded.status == :absent
    end

    test "leaves checked_in and checked_out participants unchanged when completing" do
      session_schema = insert(:program_session_schema, status: :in_progress)
      child1 = insert(:child_schema)
      child2 = insert(:child_schema)

      staff_user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      checked_in =
        insert(:participation_record_schema,
          session_id: session_schema.id,
          child_id: child1.id,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: staff_user.id
        )

      checked_out =
        insert(:participation_record_schema,
          session_id: session_schema.id,
          child_id: child2.id,
          status: :checked_out,
          check_in_at: DateTime.utc_now(),
          check_in_by: staff_user.id,
          check_out_at: DateTime.utc_now(),
          check_out_by: staff_user.id
        )

      assert {:ok, _session} = KlassHero.Participation.complete_session(admin_scope(), session_schema.id)

      assert KlassHero.Repo.get(ParticipationRecord, checked_in.id).status == :checked_in
      assert KlassHero.Repo.get(ParticipationRecord, checked_out.id).status == :checked_out
    end

    test "marks registered participants as absent when completing" do
      session_schema = insert(:program_session_schema, status: :in_progress)
      child1 = insert(:child_schema)
      child2 = insert(:child_schema)
      child3 = insert(:child_schema)

      staff_user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child1.id,
        status: :checked_in,
        check_in_at: DateTime.utc_now(),
        check_in_by: staff_user.id
      )

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child2.id,
        status: :checked_out,
        check_in_at: DateTime.utc_now(),
        check_in_by: staff_user.id,
        check_out_at: DateTime.utc_now(),
        check_out_by: staff_user.id
      )

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child3.id,
        status: :registered
      )

      assert {:ok, session} = KlassHero.Participation.complete_session(admin_scope(), session_schema.id)
      assert session.status == :completed
    end
  end

  # The gate the use case never had: until #1373 this function took a bare id and
  # authorized nothing, so any provider could complete any other business's session
  # -- which marks every remaining registered child absent.
  describe "complete_session/2 authorization" do
    test "the owning provider may complete their own session" do
      %{provider: provider, session: session} = provider_with_in_progress_session()

      assert {:ok, completed} =
               Participation.complete_session(%Scope{user: user_fixture(), provider: provider}, session.id)

      assert completed.status == :completed
    end

    test "refuses a provider who does not own the session's program" do
      %{session: session} = provider_with_in_progress_session()
      stranger = ProviderFixtures.provider_profile_fixture()

      assert {:error, :unauthorized} =
               Participation.complete_session(%Scope{user: user_fixture(), provider: stranger}, session.id)

      assert Repo.get!(ProgramSession, session.id).status == :in_progress
    end

    test "refuses an actor holding no persona" do
      %{session: session} = provider_with_in_progress_session()

      assert {:error, :unauthorized} =
               Participation.complete_session(%Scope{user: user_fixture()}, session.id)
    end

    # ADR-0019: closure gates the staff branch and only the staff branch. The
    # provider owns the roster and closes out their own season.
    test "the owning provider may still complete a Closed Program's session" do
      %{provider: provider, session: session} = provider_with_in_progress_session(closed: true)

      assert {:ok, completed} =
               Participation.complete_session(%Scope{user: user_fixture(), provider: provider}, session.id)

      assert completed.status == :completed
    end

    test "refuses a staff member on a Closed Program, naming closure as the reason" do
      %{provider: provider, program: program, session: session} =
        provider_with_in_progress_session(closed: true)

      staff = ProviderFixtures.staff_member_fixture(%{provider_id: provider.id})

      ProviderFixtures.program_assignment_fixture(%{
        provider_id: provider.id,
        staff_member_id: staff.id,
        program_id: program.id
      })

      assert {:error, :program_closed} =
               Participation.complete_session(%Scope{user: user_fixture(), staff_member: staff}, session.id)
    end
  end

  defp provider_with_in_progress_session(opts \\ []) do
    provider = ProviderFixtures.provider_profile_fixture()

    end_date = if Keyword.get(opts, :closed, false), do: Date.add(Date.utc_today(), -20)
    program = insert(:program_schema, provider_id: provider.id, end_date: end_date)
    session = insert(:program_session_schema, program_id: program.id, status: :in_progress)

    %{provider: provider, program: program, session: session}
  end

  defp user_fixture, do: AccountsFixtures.unconfirmed_user_fixture()

  # These tests are about what completing a session *does*, not who may do it, so
  # they use the persona that is authorized everywhere and stays out of the way.
  # Authorization itself is the describe block above, which builds the persona it
  # means.
  defp admin_scope, do: AccountsFixtures.admin_scope_fixture()
end
