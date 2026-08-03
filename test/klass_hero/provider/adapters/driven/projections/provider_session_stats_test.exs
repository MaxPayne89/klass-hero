defmodule KlassHero.Provider.Adapters.Driven.Projections.ProviderSessionStatsTest do
  # async: false: projection GenServers run DB queries during {:continue, :bootstrap}
  # before the test process can Sandbox.allow the spawned pid. Shared sandbox mode
  # (DataCase default when not async) covers any spawned process automatically.
  use KlassHero.DataCase, async: false

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driven.Projections.ProviderSessionStats
  alias KlassHero.Provider.SessionStats
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.Event

  defp build_session_completed_event(attrs) do
    %Event{
      event_id: Ecto.UUID.generate(),
      event_type: :session_completed,
      source_context: :participation,
      entity_type: :session,
      entity_id: attrs[:session_id] || Ecto.UUID.generate(),
      occurred_at: DateTime.utc_now(),
      payload: %{
        session_id: attrs[:session_id] || Ecto.UUID.generate(),
        program_id: attrs[:program_id] || Ecto.UUID.generate(),
        provider_id: attrs[:provider_id] || Ecto.UUID.generate(),
        program_title: attrs[:program_title] || "Test Program"
      },
      metadata: %{},
      version: 1
    }
  end

  defp start_projection! do
    {:ok, pid} =
      ProviderSessionStats.start_link(
        name: :"test_proj_#{System.unique_integer([:positive])}",
        skip_bootstrap: true
      )

    pid
  end

  describe "project/1 session_completed event" do
    test "inserts a new row on first event for a provider+program" do
      start_projection!()

      provider_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()

      event =
        build_session_completed_event(
          provider_id: provider_id,
          program_id: program_id,
          program_title: "Art Class"
        )

      ProviderSessionStats.project(event)

      stats = Repo.all(from(s in SessionStats, where: s.provider_id == ^provider_id))

      assert [stat] = stats
      assert stat.program_id == program_id
      assert stat.program_title == "Art Class"
      assert stat.sessions_completed_count == 1
    end

    test "increments count on subsequent events for same provider+program" do
      start_projection!()

      provider_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()

      event =
        build_session_completed_event(
          provider_id: provider_id,
          program_id: program_id,
          program_title: "Art Class"
        )

      for _ <- 1..3, do: ProviderSessionStats.project(event)

      stat =
        Repo.one!(
          from(s in SessionStats,
            where: s.provider_id == ^provider_id and s.program_id == ^program_id
          )
        )

      assert stat.sessions_completed_count == 3
    end

    test "tracks separate counts per program" do
      start_projection!()

      provider_id = Ecto.UUID.generate()
      program_a = Ecto.UUID.generate()
      program_b = Ecto.UUID.generate()

      ProviderSessionStats.project(
        build_session_completed_event(provider_id: provider_id, program_id: program_a, program_title: "Art")
      )

      for _ <- 1..2 do
        ProviderSessionStats.project(
          build_session_completed_event(provider_id: provider_id, program_id: program_b, program_title: "Music")
        )
      end

      stats =
        SessionStats
        |> where([s], s.provider_id == ^provider_id)
        |> order_by([s], asc: s.program_title)
        |> Repo.all()

      assert [art, music] = stats
      assert art.sessions_completed_count == 1
      assert music.sessions_completed_count == 2
    end
  end

  describe "macro invariants after happy-path startup" do
    test "state.retry_count == 0 after first event projects successfully" do
      # Start WITHOUT skip_bootstrap to exercise the real subscribe + handle_continue path.
      # If a KeyError-class bug got swallowed by the retry mixin's rescue, retry_count
      # would be > 0 even though the test event still projects correctly.
      pid =
        start_supervised!(
          {ProviderSessionStats, name: :"reg_#{System.unique_integer([:positive])}"},
          id: :regression_projection
        )

      # Drain handle_continue; bootstrap should succeed on the first attempt.
      # Shared sandbox (async: false) covers the GenServer pid automatically.
      :sys.get_state(pid)

      # If any rescue path was triggered during bootstrap, retry_count would be > 0.
      assert %{bootstrapped: true, retry_count: 0} = :sys.get_state(pid)

      # Send one well-formed event; confirm the dispatcher path doesn't trip an internal raise.
      event =
        build_session_completed_event(
          provider_id: Ecto.UUID.generate(),
          program_id: Ecto.UUID.generate(),
          program_title: "Regression Class"
        )

      assert :ok = ProviderSessionStats.project(event)

      # Projecting is not a message to this process, so its bootstrap state is untouched.
      assert %{bootstrapped: true, retry_count: 0} = :sys.get_state(pid)
    end
  end
end
