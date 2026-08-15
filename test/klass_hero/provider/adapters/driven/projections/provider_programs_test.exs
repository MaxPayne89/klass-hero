defmodule KlassHero.Provider.Adapters.Driven.Projections.ProviderProgramsTest do
  # async: false: projection GenServers run DB queries during {:continue, :bootstrap}
  # before the test process can Sandbox.allow the spawned pid. Shared sandbox mode
  # (DataCase default when not async) covers any spawned process automatically.
  use KlassHero.DataCase, async: false

  import KlassHero.Factory

  alias KlassHero.Provider.Adapters.Driven.Projections.ProviderPrograms
  alias KlassHero.Provider.ProviderProgram
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.Event

  defp build_event(event_type, payload) do
    %Event{
      event_id: Ecto.UUID.generate(),
      event_type: event_type,
      source_context: :program_catalog,
      entity_type: :program,
      entity_id: payload.program_id,
      occurred_at: DateTime.utc_now(),
      payload: payload
    }
  end

  defp start_projection! do
    {:ok, pid} =
      ProviderPrograms.start_link(
        name: :"test_proj_#{System.unique_integer([:positive])}",
        skip_bootstrap: true
      )

    pid
  end

  # Projects in the test process, exactly as the delivery job does — no mailbox, so
  # no fence. `pid` stays in the signature because these tests still need the
  # projection started for its read table to exist.
  defp send_event!(_pid, event_type, payload) do
    ProviderPrograms.project(build_event(event_type, payload))
  end

  describe "read table shape" do
    # Guards #736: `status` was projected as the constant "active" for a concept
    # Program Catalog never had. Pin the column list so a speculative field can't
    # reappear without a deliberate change here.
    test "projects exactly the columns a consumer reads" do
      assert ProviderProgram.__schema__(:fields) ==
               [:program_id, :provider_id, :name, :inserted_at, :updated_at]
    end
  end

  describe "project/1 :program_created event" do
    test "upserts a new row with provider_id and name" do
      pid = start_projection!()
      program_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      send_event!(pid, :program_created, %{
        program_id: program_id,
        provider_id: provider_id,
        title: "Drawing Club"
      })

      row = Repo.get(ProviderProgram, program_id)
      assert row.provider_id == provider_id
      assert row.name == "Drawing Club"
    end
  end

  describe "project/1 :program_updated event" do
    test "updates existing row's name without creating duplicates" do
      pid = start_projection!()
      program_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      send_event!(pid, :program_created, %{
        program_id: program_id,
        provider_id: provider_id,
        title: "Old name"
      })

      send_event!(pid, :program_updated, %{
        program_id: program_id,
        provider_id: provider_id,
        title: "New name"
      })

      assert Repo.aggregate(ProviderProgram, :count) == 1

      row = Repo.get(ProviderProgram, program_id)
      assert row.name == "New name"
    end
  end

  describe "rebuild/1" do
    test "reprojects from the write table" do
      # Trigger: write table contains a program inserted directly (e.g. via seeds)
      # Why: rebuild/1 must populate the read table without relying on integration events
      # Outcome: provider_programs reflects the write table after rebuild
      provider = insert(:provider_profile_schema)

      program =
        insert(:program_schema,
          title: "Rebuild Target Program",
          provider_id: provider.id
        )

      pid = start_projection!()

      # Sanity check: bootstrap was skipped, so the read table should still be empty
      assert Repo.get(ProviderProgram, program.id) == nil

      name = Process.info(pid, :registered_name) |> elem(1)
      assert :ok = ProviderPrograms.rebuild(name)

      row = Repo.get(ProviderProgram, program.id)
      assert row != nil
      assert row.program_id == program.id
      assert row.provider_id == provider.id
      assert row.name == "Rebuild Target Program"
    end
  end
end
