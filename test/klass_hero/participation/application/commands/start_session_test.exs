defmodule KlassHero.Participation.Application.Commands.StartSessionTest do
  @moduledoc """
  Integration tests for StartSession use case.

  Tests starting a scheduled session and transitioning it to in_progress.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation.ProgramSession

  describe "execute/1" do
    test "successfully starts a scheduled session" do
      session_schema = insert(:program_session_schema, status: :scheduled)

      assert {:ok, session} = KlassHero.Participation.start_session(session_schema.id)
      assert %ProgramSession{} = session
      assert session.id == session_schema.id
      assert session.status == :in_progress
    end

    test "returns error when session not found" do
      non_existent_id = Ecto.UUID.generate()

      assert {:error, :not_found} = KlassHero.Participation.start_session(non_existent_id)
    end

    test "returns error when starting an in_progress session" do
      session_schema = insert(:program_session_schema, status: :in_progress)

      assert {:error, :invalid_status_transition} = KlassHero.Participation.start_session(session_schema.id)
    end

    test "returns error when starting a completed session" do
      session_schema = insert(:program_session_schema, status: :completed)

      assert {:error, :invalid_status_transition} = KlassHero.Participation.start_session(session_schema.id)
    end

    test "returns error when starting a cancelled session" do
      session_schema = insert(:program_session_schema, status: :cancelled)

      assert {:error, :invalid_status_transition} = KlassHero.Participation.start_session(session_schema.id)
    end

    test "persists status change to database" do
      session_schema = insert(:program_session_schema, status: :scheduled)

      {:ok, started_session} = KlassHero.Participation.start_session(session_schema.id)

      reloaded =
        KlassHero.Repo.get(
          ProgramSession,
          session_schema.id
        )

      assert reloaded.status == :in_progress
      assert started_session.status == :in_progress
    end
  end
end
