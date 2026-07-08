defmodule KlassHero.ProgramCatalog.UpdateProgramIntegrationTest do
  use KlassHero.DataCase

  alias KlassHero.ProgramCatalog
  alias KlassHero.ProgramCatalog.Program
  alias KlassHero.ProviderFixtures
  alias KlassHero.Repo
  alias KlassHero.Shared.DomainEventBus

  describe "update_program/3" do
    setup do
      provider = ProviderFixtures.provider_profile_fixture()

      {:ok, program} =
        ProgramCatalog.create_program(%{
          provider_id: provider.id,
          title: "Original Title",
          description: "Original description",
          category: "sports",
          price: Decimal.new("100.00")
        })

      %{program: program, provider: provider}
    end

    test "updates title successfully", %{program: program, provider: provider} do
      assert {:ok, updated} =
               ProgramCatalog.update_program(provider.id, program.id, %{title: "New Title"})

      assert updated.title == "New Title"
      assert updated.description == "Original description"
    end

    test "updates multiple fields", %{program: program, provider: provider} do
      assert {:ok, updated} =
               ProgramCatalog.update_program(provider.id, program.id, %{
                 title: "Updated",
                 price: Decimal.new("200.00")
               })

      assert updated.title == "Updated"
      assert updated.price == Decimal.new("200.00")
    end

    test "rejects invalid changes (empty title)", %{program: program, provider: provider} do
      assert {:error, _} = ProgramCatalog.update_program(provider.id, program.id, %{title: ""})

      # Verify original unchanged
      assert {:ok, unchanged} = ProgramCatalog.get_program_by_id(program.id)
      assert unchanged.title == "Original Title"
    end

    test "returns not_found for invalid ID", %{provider: provider} do
      assert {:error, :not_found} =
               ProgramCatalog.update_program(provider.id, Ecto.UUID.generate(), %{title: "New"})
    end

    test "returns not_found and leaves the row unchanged when another provider owns it", %{
      program: program
    } do
      other = ProviderFixtures.provider_profile_fixture()

      # IDOR guard: a foreign provider_id must not update — and must be
      # indistinguishable from a genuine miss (no existence leak).
      assert {:error, :not_found} =
               ProgramCatalog.update_program(other.id, program.id, %{title: "Hijacked"})

      assert {:ok, unchanged} = ProgramCatalog.get_program_by_id(program.id)
      assert unchanged.title == "Original Title"
    end

    test "dispatches schedule event when scheduling fields change", %{
      program: program,
      provider: provider
    } do
      # Subscribe a handler to capture schedule update events
      test_pid = self()

      DomainEventBus.subscribe(
        KlassHero.ProgramCatalog,
        :program_schedule_updated,
        fn event ->
          send(test_pid, {:schedule_event, event})
          :ok
        end
      )

      assert {:ok, _updated} =
               ProgramCatalog.update_program(provider.id, program.id, %{
                 meeting_days: ["Monday", "Wednesday"]
               })

      assert_receive {:schedule_event, event}
      assert event.event_type == :program_schedule_updated
      assert event.payload.program_id == program.id
      assert event.payload.provider_id == provider.id
      assert event.payload.meeting_days == ["Monday", "Wednesday"]
      assert Map.has_key?(event.payload, :meeting_start_time)
      assert Map.has_key?(event.payload, :meeting_end_time)
      assert Map.has_key?(event.payload, :start_date)
      assert Map.has_key?(event.payload, :end_date)
    end

    test "does not dispatch schedule event for non-schedule changes", %{
      program: program,
      provider: provider
    } do
      test_pid = self()

      DomainEventBus.subscribe(
        KlassHero.ProgramCatalog,
        :program_schedule_updated,
        fn event ->
          send(test_pid, {:schedule_event, event})
          :ok
        end
      )

      assert {:ok, _updated} =
               ProgramCatalog.update_program(provider.id, program.id, %{title: "New Title"})

      refute_receive {:schedule_event, _}, 100
    end

    test "dispatches single event for multiple schedule field changes", %{
      program: program,
      provider: provider
    } do
      test_pid = self()

      DomainEventBus.subscribe(
        KlassHero.ProgramCatalog,
        :program_schedule_updated,
        fn event ->
          send(test_pid, {:schedule_event, event})
          :ok
        end
      )

      assert {:ok, _updated} =
               ProgramCatalog.update_program(provider.id, program.id, %{
                 meeting_days: ["Tuesday", "Thursday"],
                 meeting_start_time: ~T[14:00:00],
                 meeting_end_time: ~T[15:30:00]
               })

      assert_receive {:schedule_event, _event}
      refute_receive {:schedule_event, _}, 100
    end

    test "optimistic lock raises StaleEntryError on a stale version", %{program: program} do
      # Load the row, then bump its version behind the loaded struct's back.
      stale = Repo.get!(Program, program.id)

      Repo.get!(Program, program.id)
      |> Ecto.Changeset.change(%{})
      |> Ecto.Changeset.force_change(:lock_version, 99)
      |> Repo.update!()

      # update_changeset carries the stale lock_version (1); the DB row is at 99,
      # so the guarded UPDATE matches no rows and Ecto raises. update_program/2
      # rescues this into {:error, :stale_data}.
      assert_raise Ecto.StaleEntryError, fn ->
        stale
        |> Program.update_changeset(%{title: "Stale Edit"})
        |> Repo.update!()
      end
    end
  end
end
