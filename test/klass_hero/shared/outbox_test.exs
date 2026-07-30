defmodule KlassHero.Shared.OutboxTest do
  # async: false — the ObanOutbox describe swaps the :outbox adapter in application
  # env, which every other test reads. Concurrent tests would suddenly enqueue for
  # real (and, under inline mode, execute) instead of recording.
  use KlassHero.DataCase, async: false

  import Ecto.Query
  import KlassHero.Factory

  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Events.ObanOutbox
  alias KlassHero.Shared.Adapters.Driven.Events.TestOutbox
  alias KlassHero.Shared.Domain.Events.Event
  alias KlassHero.Shared.Outbox

  setup do
    TestOutbox.setup()
    :ok
  end

  defp event(type, entity_id, payload \\ %{}) do
    Event.new(type, :program_catalog, :program, entity_id, payload)
  end

  defp staged_job_events do
    Repo.all(from(j in "oban_jobs", where: j.worker == ^worker_name(), select: j.args))
  end

  defp worker_name, do: "KlassHero.Shared.Adapters.Driven.Workers.EventDeliveryWorker"

  # The promoter used to decide this by omission: an event type with no `promote/1`
  # clause staged nothing. Asking the routing table asks the same question of the
  # thing that already answers it — measured at the time of writing, all 38 event
  # types produced anywhere in `lib/` have a registered consumer, so this filter
  # drops nothing that exists today.
  describe "staging what someone consumes" do
    test "stages an event a consumer is registered for" do
      Outbox.stage(
        KlassHero.ProgramCatalog,
        event(:program_created, "prog-1")
      )

      assert [%Event{event_type: :program_created}] = TestOutbox.staged()
    end

    test "stages nothing when no consumer is registered for the topic" do
      Outbox.stage(
        KlassHero.ProgramCatalog,
        event(:program_archived, "prog-1")
      )

      assert [] = TestOutbox.staged()
    end

    test "keeps the order the producer emitted" do
      Outbox.stage(KlassHero.ProgramCatalog, [
        event(:program_created, "prog-1"),
        event(:program_updated, "prog-2"),
        event(:program_created, "prog-3")
      ])

      assert ["prog-1", "prog-2", "prog-3"] = Enum.map(TestOutbox.staged(), & &1.entity_id)
    end

    # Filtering per event, not per batch: one unrouted event must not strand the
    # siblings staged in the same transaction.
    test "keeps the consumed events from a batch that also holds unconsumed ones" do
      Outbox.stage(KlassHero.ProgramCatalog, [
        event(:program_archived, "prog-1"),
        event(:program_created, "prog-2"),
        event(:program_archived, "prog-3")
      ])

      assert ["prog-2"] = Enum.map(TestOutbox.staged(), & &1.entity_id)
    end
  end

  describe "transact/2" do
    test "stages the events the callback returned and returns the result alone" do
      assert {:ok, :the_entity} =
               Outbox.transact(KlassHero.ProgramCatalog, fn ->
                 {:ok, :the_entity, [event(:program_created, "prog-1", %{title: "Chess"})]}
               end)

      assert [%Event{event_type: :program_created}] = TestOutbox.staged()
    end

    test "rolls back with the callback's own reason, so callers match what they matched before" do
      assert {:error, :nope} = Outbox.transact(KlassHero.ProgramCatalog, fn -> {:error, :nope} end)

      assert [] = TestOutbox.staged()
    end

    # The one caller that needs them is Participation, which announces each event to
    # its LiveViews after the commit — it cannot do that from a result it never sees.
    test "transact_with_events/2 hands the staged events back alongside the result" do
      assert {:ok, {:the_entity, [%Event{event_type: :program_created}]}} =
               Outbox.transact_with_events(KlassHero.ProgramCatalog, fn ->
                 {:ok, :the_entity, [event(:program_created, "prog-1", %{title: "Chess"})]}
               end)
    end

    test "transact_with_events/2 rolls back with the callback's own reason" do
      assert {:error, :nope} =
               Outbox.transact_with_events(KlassHero.ProgramCatalog, fn -> {:error, :nope} end)

      assert [] = TestOutbox.staged()
    end

    test "a write in the callback is undone when a later step fails" do
      provider = insert(:provider_profile_schema)

      assert {:error, :changed_my_mind} =
               Outbox.transact(KlassHero.ProgramCatalog, fn ->
                 Repo.delete!(provider)
                 {:error, :changed_my_mind}
               end)

      assert Repo.get(ProviderProfile, provider.id)
    end

    # A half-migrated producer returning {:ok, entity} must fail loudly on its first
    # run rather than quietly staging nothing.
    test "raises when the callback does not return events" do
      assert_raise CaseClauseError, fn ->
        Outbox.transact(KlassHero.ProgramCatalog, fn -> {:ok, :the_entity} end)
      end
    end
  end

  # The suite runs Oban `testing: :inline`, which executes a job at insert instead of
  # writing a row — so under it there is no job to be transactional about, and real
  # consumers run mid-transaction. `with_testing_mode(:manual, ...)` restores the
  # production insert path for these two, which is the only way to observe the
  # property they exist for.
  describe "transactional staging" do
    setup do
      original = Application.get_env(:klass_hero, :outbox)
      Application.put_env(:klass_hero, :outbox, module: ObanOutbox)
      on_exit(fn -> Application.put_env(:klass_hero, :outbox, original) end)
    end

    test "a committed transaction leaves exactly one job carrying its events" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, :done} =
          Repo.transaction(fn ->
            Outbox.stage(KlassHero.ProgramCatalog, [
              event(:program_created, "prog-1", %{title: "Chess"}),
              event(:program_updated, "prog-1", %{title: "Chess Club"})
            ])

            :done
          end)

        assert [%{"events" => [%{"event_type" => "program_created"}, %{"event_type" => "program_updated"}]}] =
                 staged_job_events()
      end)
    end

    # The regression test for #1190. Before the outbox the publish happened after the
    # commit, on the next line, so a crash in between lost the event with the write
    # already durable. Now there is one commit and nothing to be between.
    test "a rolled-back transaction leaves no job" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:error, :nope} =
          Repo.transaction(fn ->
            Outbox.stage(KlassHero.ProgramCatalog, event(:program_created, "prog-1", %{title: "Chess"}))

            Repo.rollback(:nope)
          end)

        assert [] = staged_job_events()
      end)
    end
  end
end
