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
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.Outbox

  setup do
    TestOutbox.setup()
    :ok
  end

  defp domain_event(type, aggregate_id, payload) do
    DomainEvent.new(type, aggregate_id, :program, payload)
  end

  defp staged_job_events do
    Repo.all(from(j in "oban_jobs", where: j.worker == ^worker_name(), select: j.args))
  end

  defp worker_name, do: "KlassHero.Shared.Adapters.Driven.Workers.EventDeliveryWorker"

  describe "promotion" do
    test "maps a domain event to its context's integration event" do
      Outbox.stage(KlassHero.ProgramCatalog, domain_event(:program_created, "prog-1", %{title: "Chess"}))

      assert [%IntegrationEvent{event_type: :program_created, source_context: :program_catalog, entity_id: "prog-1"}] =
               TestOutbox.staged()
    end

    test "passes an integration event through untouched" do
      event = IntegrationEvent.new(:program_created, :program_catalog, :program, "prog-1", %{title: "Chess"})

      Outbox.stage(KlassHero.ProgramCatalog, event)

      assert [^event] = TestOutbox.staged()
    end

    # A domain event with no promoter clause was never promoted under the bus either —
    # it simply had no registration. Staging nothing keeps that exact behaviour.
    test "stages nothing for an event type the context does not promote" do
      Outbox.stage(KlassHero.ProgramCatalog, domain_event(:program_archived, "prog-1", %{}))

      assert [] = TestOutbox.staged()
    end

    test "stages nothing for a context with no promoter at all" do
      Outbox.stage(KlassHero.Admin, domain_event(:program_created, "prog-1", %{title: "Chess"}))

      assert [] = TestOutbox.staged()
    end

    test "keeps the order the producer emitted" do
      Outbox.stage(KlassHero.ProgramCatalog, [
        domain_event(:program_created, "prog-1", %{title: "First"}),
        domain_event(:program_updated, "prog-2", %{title: "Second"}),
        domain_event(:program_created, "prog-3", %{title: "Third"})
      ])

      assert ["prog-1", "prog-2", "prog-3"] = Enum.map(TestOutbox.staged(), & &1.entity_id)
    end
  end

  # The promoter used to decide this by omission: an event type with no `promote/1`
  # clause staged nothing. Asking the routing table asks the same question of the
  # thing that already answers it — measured at the time of writing, all 38 event
  # types produced anywhere in `lib/` have a registered consumer, so this filter
  # drops nothing that exists today.
  describe "staging what someone consumes" do
    test "stages an event a consumer is registered for" do
      Outbox.stage(
        KlassHero.ProgramCatalog,
        IntegrationEvent.new(:program_created, :program_catalog, :program, "prog-1", %{})
      )

      assert [%IntegrationEvent{event_type: :program_created}] = TestOutbox.staged()
    end

    test "stages nothing when no consumer is registered for the topic" do
      Outbox.stage(
        KlassHero.ProgramCatalog,
        IntegrationEvent.new(:program_archived, :program_catalog, :program, "prog-1", %{})
      )

      assert [] = TestOutbox.staged()
    end

    # Filtering per event, not per batch: one unrouted event must not strand the
    # siblings staged in the same transaction.
    test "keeps the consumed events from a batch that also holds unconsumed ones" do
      Outbox.stage(KlassHero.ProgramCatalog, [
        IntegrationEvent.new(:program_archived, :program_catalog, :program, "prog-1", %{}),
        IntegrationEvent.new(:program_created, :program_catalog, :program, "prog-2", %{}),
        IntegrationEvent.new(:program_archived, :program_catalog, :program, "prog-3", %{})
      ])

      assert ["prog-2"] = Enum.map(TestOutbox.staged(), & &1.entity_id)
    end
  end

  describe "transact/2" do
    test "stages the events the callback returned and hands them back with the result" do
      assert {:ok, {:the_entity, [_event]}} =
               Outbox.transact(KlassHero.ProgramCatalog, fn ->
                 {:ok, :the_entity, [domain_event(:program_created, "prog-1", %{title: "Chess"})]}
               end)

      assert [%IntegrationEvent{event_type: :program_created}] = TestOutbox.staged()
    end

    test "rolls back with the callback's own reason, so callers match what they matched before" do
      assert {:error, :nope} = Outbox.transact(KlassHero.ProgramCatalog, fn -> {:error, :nope} end)

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
              domain_event(:program_created, "prog-1", %{title: "Chess"}),
              domain_event(:program_updated, "prog-1", %{title: "Chess Club"})
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
            Outbox.stage(KlassHero.ProgramCatalog, domain_event(:program_created, "prog-1", %{title: "Chess"}))

            Repo.rollback(:nope)
          end)

        assert [] = staged_job_events()
      end)
    end
  end
end
