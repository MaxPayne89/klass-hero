defmodule KlassHero.Participation.CreateSessionTest do
  @moduledoc """
  Integration tests for CreateSession use case.

  Tests session creation with domain validation and persistence.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Provider.ProviderProfile

  describe "execute/1" do
    test "successfully creates a session with valid attributes" do
      program = insert(:program_schema)

      assert {:ok, session} =
               KlassHero.Participation.create_session(owner_scope(program), %{
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
               KlassHero.Participation.create_session(owner_scope(program), %{
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
               KlassHero.Participation.create_session(owner_scope(program), %{
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
               KlassHero.Participation.create_session(owner_scope(program), %{
                 program_id: program.id,
                 session_date: ~D[2025-02-15],
                 start_time: ~T[14:00:00],
                 end_time: ~T[09:00:00],
                 max_capacity: 20
               })

      assert reason == :invalid_time_range
    end

    test "allows sessions with different dates for same program" do
      program = insert(:program_schema)

      assert {:ok, _session1} =
               KlassHero.Participation.create_session(owner_scope(program), %{
                 program_id: program.id,
                 session_date: ~D[2025-02-15],
                 start_time: ~T[09:00:00],
                 end_time: ~T[12:00:00],
                 max_capacity: 20
               })

      assert {:ok, session2} =
               KlassHero.Participation.create_session(owner_scope(program), %{
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
               KlassHero.Participation.create_session(owner_scope(program), %{
                 program_id: program.id,
                 session_date: ~D[2025-02-15],
                 start_time: ~T[09:00:00],
                 end_time: ~T[12:00:00],
                 max_capacity: 20
               })

      assert {:ok, session2} =
               KlassHero.Participation.create_session(owner_scope(program), %{
                 program_id: program.id,
                 session_date: ~D[2025-02-15],
                 start_time: ~T[14:00:00],
                 end_time: ~T[17:00:00],
                 max_capacity: 20
               })

      assert session2.start_time == ~T[14:00:00]
    end
  end

  # The guard used to live in SessionsLive as a `provider_program_ids` MapSet test,
  # so a caller reaching the context directly had none. #1074 added a second create
  # surface, which is exactly the shape ADR-0019 warns about — hence these assert
  # the refusal *at the context*, not at a LiveView.
  describe "authorization" do
    test "refuses a provider who does not own the program" do
      program = insert(:program_schema)
      foreign = %Scope{provider: %ProviderProfile{id: Ecto.UUID.generate()}}

      assert {:error, :unauthorized} =
               KlassHero.Participation.create_session(foreign, %{
                 program_id: program.id,
                 session_date: ~D[2025-02-15],
                 start_time: ~T[09:00:00],
                 end_time: ~T[12:00:00],
                 max_capacity: 20
               })
    end

    test "refuses before validating, so an unauthorized caller learns nothing about the params" do
      program = insert(:program_schema)
      foreign = %Scope{provider: %ProviderProfile{id: Ecto.UUID.generate()}}

      # end_time before start_time would be :invalid_time_range if it got that far.
      assert {:error, :unauthorized} =
               KlassHero.Participation.create_session(foreign, %{
                 program_id: program.id,
                 session_date: ~D[2025-02-15],
                 start_time: ~T[14:00:00],
                 end_time: ~T[09:00:00],
                 max_capacity: 20
               })
    end

    test "refuses a scope holding no persona at all" do
      program = insert(:program_schema)

      assert {:error, :unauthorized} =
               KlassHero.Participation.create_session(%Scope{}, %{
                 program_id: program.id,
                 session_date: ~D[2025-02-15],
                 start_time: ~T[09:00:00],
                 end_time: ~T[12:00:00],
                 max_capacity: 20
               })
    end
  end

  # Only `provider.id` is read on this path, so the profile need not be a real row —
  # `provider_owns?/2` compares it against what the resolver reads from `programs`.
  defp owner_scope(program) do
    %Scope{provider: %ProviderProfile{id: program.provider_id}}
  end
end
