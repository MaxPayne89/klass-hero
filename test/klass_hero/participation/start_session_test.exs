defmodule KlassHero.Participation.StartSessionTest do
  @moduledoc """
  Integration tests for StartSession use case.

  Tests starting a scheduled session and transitioning it to in_progress.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Participation
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.ProviderFixtures

  describe "execute/1" do
    test "successfully starts a scheduled session" do
      session_schema = insert(:program_session_schema, status: :scheduled)

      assert {:ok, session} = KlassHero.Participation.start_session(admin_scope(), session_schema.id)
      assert %ProgramSession{} = session
      assert session.id == session_schema.id
      assert session.status == :in_progress
    end

    test "returns error when session not found" do
      non_existent_id = Ecto.UUID.generate()

      assert {:error, :not_found} = KlassHero.Participation.start_session(admin_scope(), non_existent_id)
    end

    test "returns error when starting an in_progress session" do
      session_schema = insert(:program_session_schema, status: :in_progress)

      assert {:error, :invalid_status_transition} =
               KlassHero.Participation.start_session(admin_scope(), session_schema.id)
    end

    test "returns error when starting a completed session" do
      session_schema = insert(:program_session_schema, status: :completed)

      assert {:error, :invalid_status_transition} =
               KlassHero.Participation.start_session(admin_scope(), session_schema.id)
    end

    test "returns error when starting a cancelled session" do
      session_schema = insert(:program_session_schema, status: :cancelled)

      assert {:error, :invalid_status_transition} =
               KlassHero.Participation.start_session(admin_scope(), session_schema.id)
    end

    test "persists status change to database" do
      session_schema = insert(:program_session_schema, status: :scheduled)

      {:ok, started_session} = KlassHero.Participation.start_session(admin_scope(), session_schema.id)

      reloaded =
        KlassHero.Repo.get(
          ProgramSession,
          session_schema.id
        )

      assert reloaded.status == :in_progress
      assert started_session.status == :in_progress
    end
  end

  # start_session shares complete_session's gate and its history: both took a bare
  # id until #1373. Starting a session is the less destructive of the two, but an
  # ungated write on someone else's roster is still theirs to make, not ours.
  describe "start_session/2 authorization" do
    test "the owning provider may start their own session" do
      %{provider: provider, session: session} = provider_with_scheduled_session()

      assert {:ok, started} =
               Participation.start_session(%Scope{user: user_fixture(), provider: provider}, session.id)

      assert started.status == :in_progress
    end

    test "refuses a provider who does not own the session's program" do
      %{session: session} = provider_with_scheduled_session()
      stranger = ProviderFixtures.provider_profile_fixture()

      assert {:error, :unauthorized} =
               Participation.start_session(%Scope{user: user_fixture(), provider: stranger}, session.id)

      assert KlassHero.Repo.get!(ProgramSession, session.id).status == :scheduled
    end

    test "refuses an actor holding no persona" do
      %{session: session} = provider_with_scheduled_session()

      assert {:error, :unauthorized} =
               Participation.start_session(%Scope{user: user_fixture()}, session.id)
    end

    test "refuses a staff member on a Closed Program, naming closure as the reason" do
      %{provider: provider, program: program, session: session} =
        provider_with_scheduled_session(closed: true)

      staff = ProviderFixtures.staff_member_fixture(%{provider_id: provider.id})

      ProviderFixtures.program_assignment_fixture(%{
        provider_id: provider.id,
        staff_member_id: staff.id,
        program_id: program.id
      })

      assert {:error, :program_closed} =
               Participation.start_session(%Scope{user: user_fixture(), staff_member: staff}, session.id)
    end
  end

  defp provider_with_scheduled_session(opts \\ []) do
    provider = ProviderFixtures.provider_profile_fixture()

    end_date = if Keyword.get(opts, :closed, false), do: Date.add(Date.utc_today(), -20)
    program = insert(:program_schema, provider_id: provider.id, end_date: end_date)
    session = insert(:program_session_schema, program_id: program.id, status: :scheduled)

    %{provider: provider, program: program, session: session}
  end

  defp user_fixture, do: AccountsFixtures.unconfirmed_user_fixture()

  # These tests are about what starting a session *does*, not who may do it, so
  # they use the persona that is authorized everywhere and stays out of the way.
  defp admin_scope, do: AccountsFixtures.admin_scope_fixture()
end
