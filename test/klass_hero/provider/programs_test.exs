defmodule KlassHero.Provider.ProgramsTest do
  @moduledoc """
  Integration tests for the provider programs/sessions read queries.

  Tests the complete data flow: Facade -> Programs -> Database -> read model.
  Everything on `KlassHero.Provider`'s public surface is exercised through the
  facade; `get_session_detail/1` is context-internal and called directly.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.Programs
  alias KlassHero.Provider.ProviderProgram
  alias KlassHero.Provider.SessionDetail
  alias KlassHero.Repo

  describe "unknown identifiers" do
    test "every read returns its empty value rather than raising" do
      absent = Ecto.UUID.generate()

      cases = [
        {"get_provider_program/1", fn -> Programs.get_provider_program(absent) end, {:error, :not_found}},
        {"get_provider_program/2", fn -> Programs.get_provider_program(absent, absent) end, {:error, :not_found}},
        {"get_session_detail/1", fn -> Programs.get_session_detail(absent) end, {:error, :not_found}},
        {"list_provider_programs/1", fn -> Provider.list_provider_programs(absent) end, []},
        {"list_program_sessions/2", fn -> Provider.list_program_sessions(absent, absent) end, []},
        {"get_total_session_count/1", fn -> Provider.get_total_session_count(absent) end, 0}
      ]

      for {label, call, expected} <- cases do
        assert call.() == expected, "#{label} should return #{inspect(expected)} for an unknown id"
      end
    end
  end

  describe "list_program_sessions/2" do
    test "returns sessions for the provider's program ordered by date and start time" do
      provider_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()

      insert_session(%{
        program_id: program_id,
        provider_id: provider_id,
        session_date: ~D[2026-05-02],
        start_time: ~T[09:00:00]
      })

      insert_session(%{
        program_id: program_id,
        provider_id: provider_id,
        session_date: ~D[2026-05-01],
        start_time: ~T[15:00:00]
      })

      [first, second] = Provider.list_program_sessions(provider_id, program_id)

      assert %SessionDetail{session_date: ~D[2026-05-01]} = first
      assert %SessionDetail{session_date: ~D[2026-05-02]} = second
    end

    test "does not leak sessions across providers" do
      program_id = Ecto.UUID.generate()
      mine = Ecto.UUID.generate()
      theirs = Ecto.UUID.generate()

      insert_session(%{program_id: program_id, provider_id: theirs})

      assert [] == Provider.list_program_sessions(mine, program_id)
    end
  end

  describe "get_session_detail/1" do
    test "returns {:ok, session_detail} for a known session_id" do
      provider_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()

      insert_session(%{session_id: session_id, program_id: program_id, provider_id: provider_id})

      assert {:ok, %SessionDetail{} = detail} = Programs.get_session_detail(session_id)
      assert detail.session_id == session_id
      assert detail.provider_id == provider_id
      assert detail.program_id == program_id
    end
  end

  describe "get_provider_program/1" do
    test "returns {:ok, struct} for a known program_id, unscoped" do
      row = insert_program(%{name: "Robotics"})

      assert {:ok, %ProviderProgram{program_id: id, name: "Robotics"}} =
               Programs.get_provider_program(row.program_id)

      assert id == row.program_id
    end
  end

  describe "get_provider_program/2" do
    test "returns the program when the provider owns it" do
      provider_id = Ecto.UUID.generate()
      row = insert_program(%{provider_id: provider_id, name: "Chess"})

      assert {:ok, %ProviderProgram{name: "Chess"}} =
               Programs.get_provider_program(row.program_id, provider_id)
    end

    # Foreign ≡ missing: the provider_id predicate is part of the query, so a
    # foreign row is never loaded and the caller gains no existence oracle.
    test "returns :not_found for a program owned by someone else" do
      row = insert_program(%{provider_id: Ecto.UUID.generate()})

      assert {:error, :not_found} =
               Programs.get_provider_program(row.program_id, Ecto.UUID.generate())
    end
  end

  describe "list_provider_programs/1" do
    test "returns only rows for the given provider, ordered by name asc" do
      provider_id = Ecto.UUID.generate()
      insert_program(%{provider_id: provider_id, name: "Chess"})
      insert_program(%{provider_id: provider_id, name: "Art"})
      insert_program(%{provider_id: Ecto.UUID.generate(), name: "Stranger"})

      rows = Provider.list_provider_programs(provider_id)

      assert Enum.map(rows, & &1.name) == ["Art", "Chess"]
      assert Enum.all?(rows, &(&1.provider_id == provider_id))
    end
  end

  describe "get_total_session_count/1" do
    # Counting rules (statuses, cross-provider isolation) are pinned in
    # ParticipationSessionStatsACLTest; this asserts the facade reaches them.
    test "returns the count of completed sessions across the provider's programs" do
      provider = insert(:provider_profile_schema)
      art = insert(:program_schema, provider_id: provider.id, title: "Art")
      chess = insert(:program_schema, provider_id: provider.id, title: "Chess")

      for {program, status, date} <- [
            {art, "completed", ~D[2026-05-01]},
            {art, "completed", ~D[2026-05-02]},
            {chess, "completed", ~D[2026-05-03]},
            {chess, "scheduled", ~D[2026-05-04]}
          ] do
        insert(:program_session_schema, program_id: program.id, status: status, session_date: date)
      end

      assert 3 == Provider.get_total_session_count(provider.id)
    end
  end

  defp insert_session(attrs) do
    defaults = %{
      session_id: Ecto.UUID.generate(),
      program_title: "Judo",
      session_date: ~D[2026-05-01],
      start_time: ~T[09:00:00],
      end_time: ~T[10:00:00],
      status: :scheduled
    }

    %SessionDetail{}
    |> Ecto.Changeset.change(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_program(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    defaults = %{
      program_id: Ecto.UUID.generate(),
      provider_id: Ecto.UUID.generate(),
      name: "Drawing Club",
      inserted_at: now,
      updated_at: now
    }

    Repo.insert!(struct(ProviderProgram, Map.merge(defaults, attrs)))
  end
end
