defmodule KlassHero.Shared.Adapters.Driven.Workers.EventDeliveryWorkerTest do
  use KlassHero.DataCase, async: false

  import ExUnit.CaptureLog

  alias KlassHero.Shared.Adapters.Driven.Events.EventSerializer
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.ProcessedEvent
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.UndeliveredEvent
  alias KlassHero.Shared.Adapters.Driven.Workers.EventDeliveryWorker
  alias KlassHero.Shared.Domain.Events.Event
  alias KlassHero.Shared.EventDispatcher

  @topic "integration:test_context:thing_happened"

  defmodule Recorder do
    @moduledoc false

    def calls, do: Agent.get(__MODULE__, &Enum.reverse/1)
    defp record(entry), do: Agent.update(__MODULE__, &[entry | &1])

    def first(%Event{} = event), do: record({:first, event.entity_id})
    def second(%Event{} = event), do: record({:second, event.entity_id})

    def flaky(%Event{} = event) do
      record({:flaky, event.entity_id})
      {:error, :not_today}
    end
  end

  setup do
    start_supervised!(%{id: Recorder, start: {Agent, :start_link, [fn -> [] end, [name: Recorder]]}})

    original = Application.get_env(:klass_hero, :event_consumers)
    on_exit(fn -> Application.put_env(:klass_hero, :event_consumers, original) end)

    {:ok, original: original}
  end

  defp route(consumers, %{original: original}) do
    Application.put_env(:klass_hero, :event_consumers, Map.put(original, @topic, consumers))
  end

  defp event(entity_id) do
    Event.new(:thing_happened, :test_context, :thing, entity_id, %{})
  end

  defp job(events, attempt \\ 1) do
    %Oban.Job{
      id: 4242,
      args: %{"events" => Enum.map(events, &EventSerializer.serialize/1)},
      attempt: attempt,
      max_attempts: 10,
      discarded_at: DateTime.utc_now()
    }
  end

  # A row staged before #1326 *and* before #1358: it carries a `"metadata"` map holding
  # `"criticality"`, plus a `"version"`. No module holds the `criticality` atom any more,
  # and neither top-level key has a field to land in since #1358 — so a serializer that
  # atomized whatever arrived would raise here, and again in `compensate/2`, losing the
  # event with no `undelivered_events` row to find it by. Both routes are covered because
  # the second is the one nothing else would have caught.
  #
  # The assertions deliberately say nothing about the retired keys. What is being proved
  # is that an old row still *delivers*, which is the guarantee that has to survive every
  # future retirement, not the mechanism any one of them used.
  defp legacy_job(events) do
    job = job(events)

    staged =
      Enum.map(
        job.args["events"],
        &Map.merge(&1, %{"metadata" => %{"criticality" => "critical"}, "version" => 1})
      )

    %{job | args: %{"events" => staged}}
  end

  defp handler_ref(consumer), do: EventDispatcher.handler_ref(consumer)

  defp mark_processed(event, consumer) do
    Repo.insert!(%ProcessedEvent{
      event_id: event.event_id,
      handler_ref: handler_ref(consumer),
      processed_at: DateTime.utc_now()
    })
  end

  defp undelivered(%{event_id: event_id}) do
    Repo.get_by(UndeliveredEvent, event_id: event_id)
  end

  defp worker_name, do: Oban.Worker.to_string(EventDeliveryWorker)

  # Through the real compensation, so the row under replay is the row production
  # writes — payload, missed consumers and all.
  defp dead_letter(event, _ctx) do
    :ok = EventDeliveryWorker.compensate(job([event]), "boom")
    undelivered(event)
  end

  # `testing: :inline` would run the delivery job at insert, inside `replay/1`'s own
  # transaction — a sequencing production never has (.claude/rules/testing.md).
  defp replay(row) do
    Oban.Testing.with_testing_mode(:manual, fn -> EventDeliveryWorker.replay(row) end)
  end

  defp deliver_replay(row) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      :ok = EventDeliveryWorker.replay(row)
      Oban.drain_queue(queue: :events, with_recursion: true)
    end)
  end

  test "delivers each event to every consumer of its topic", ctx do
    route([{Recorder, :first}, {Recorder, :second}], ctx)

    assert :ok = EventDeliveryWorker.perform(job([event("thing-1")]))

    assert [{:first, "thing-1"}, {:second, "thing-1"}] = Recorder.calls()
  end

  test "delivers a job staged before the criticality field was removed", ctx do
    route([{Recorder, :first}], ctx)

    assert :ok = EventDeliveryWorker.perform(legacy_job([event("thing-1")]))

    assert [{:first, "thing-1"}] = Recorder.calls()
  end

  test "delivers a job's events in the order they were staged", ctx do
    route([{Recorder, :first}], ctx)

    assert :ok = EventDeliveryWorker.perform(job([event("a"), event("b"), event("c")]))

    assert [{:first, "a"}, {:first, "b"}, {:first, "c"}] = Recorder.calls()
  end

  test "records each delivery so a retry does not run it again", ctx do
    route([{Recorder, :first}], ctx)
    event = event("thing-1")

    assert :ok = EventDeliveryWorker.perform(job([event]))
    assert :ok = EventDeliveryWorker.perform(job([event], 2))

    assert [{:first, "thing-1"}] = Recorder.calls()

    assert Repo.get_by(ProcessedEvent,
             event_id: event.event_id,
             handler_ref: EventDispatcher.handler_ref({Recorder, :first})
           )
  end

  describe "when a consumer fails" do
    test "returns an error so Oban retries the job", ctx do
      route([{Recorder, :flaky}], ctx)

      assert capture_log(fn ->
               assert {:error, :not_today} = EventDeliveryWorker.perform(job([event("thing-1")]))
             end) =~ "Event delivery failed (attempt 1/10)"
    end

    test "still delivers to the consumers after it", ctx do
      route([{Recorder, :flaky}, {Recorder, :second}], ctx)

      capture_log(fn ->
        assert {:error, :not_today} = EventDeliveryWorker.perform(job([event("thing-1")]))
      end)

      assert [{:flaky, "thing-1"}, {:second, "thing-1"}] = Recorder.calls()
    end

    # One poisoned event must not strand the rest of its transaction's events.
    test "still delivers the events after it", ctx do
      route([{Recorder, :flaky}], ctx)

      capture_log(fn ->
        assert {:error, :not_today} = EventDeliveryWorker.perform(job([event("a"), event("b")]))
      end)

      assert [{:flaky, "a"}, {:flaky, "b"}] = Recorder.calls()
    end

    # Error level is what ErrorTracker alerts on, so it must wait for the last attempt.
    test "logs at error level only once retries are exhausted", ctx do
      route([{Recorder, :flaky}], ctx)

      log =
        capture_log(fn ->
          assert {:error, :not_today} = EventDeliveryWorker.perform(job([event("thing-1")], 10))
        end)

      assert log =~ "permanently failed after 10 attempts"
    end
  end

  test "a topic with no consumers is delivered to nobody and succeeds", ctx do
    route([], ctx)

    assert :ok = EventDeliveryWorker.perform(job([event("thing-1")]))
    assert [] = Recorder.calls()
  end

  describe "compensate/2" do
    test "records the event and the consumers that never received it", ctx do
      route([{Recorder, :first}, {Recorder, :second}], ctx)
      event = event("thing-1")

      assert :ok = EventDeliveryWorker.compensate(job([event]), "boom")

      row = undelivered(event)
      assert row.topic == @topic
      assert row.job_id == 4242
      assert row.discarded_at
      assert row.missed_consumers == [handler_ref({Recorder, :first}), handler_ref({Recorder, :second})]
    end

    test "records a job staged before the criticality field was removed", ctx do
      route([{Recorder, :first}], ctx)
      event = event("thing-1")

      assert :ok = EventDeliveryWorker.compensate(legacy_job([event]), "boom")

      assert undelivered(event).missed_consumers == [handler_ref({Recorder, :first})]
    end

    # Replay hands these args straight back to the worker, so the whole envelope has
    # to survive — not just the event's own payload.
    test "keeps the serialized envelope so the event can be replayed", ctx do
      route([{Recorder, :first}], ctx)
      event = event("thing-1")

      assert :ok = EventDeliveryWorker.compensate(job([event]), nil)

      assert undelivered(event).payload == EventSerializer.serialize(event)
    end

    # The loss is partial: `processed_events` keeps the consumers that did run, and a
    # retry only ever re-runs the rest. Recording the ones that succeeded would
    # overstate what was lost.
    test "records only the consumers still outstanding", ctx do
      route([{Recorder, :first}, {Recorder, :second}], ctx)
      event = event("thing-1")
      mark_processed(event, {Recorder, :first})

      assert :ok = EventDeliveryWorker.compensate(job([event]), "boom")

      assert undelivered(event).missed_consumers == [handler_ref({Recorder, :second})]
    end

    test "records nothing for an event every consumer received", ctx do
      route([{Recorder, :first}], ctx)
      event = event("thing-1")
      mark_processed(event, {Recorder, :first})

      assert :ignore = EventDeliveryWorker.compensate(job([event]), "boom")

      refute undelivered(event)
    end

    test "records only the undelivered events of a job that lost some of them", ctx do
      route([{Recorder, :first}], ctx)
      delivered = event("a")
      lost = event("b")
      mark_processed(delivered, {Recorder, :first})

      assert :ok = EventDeliveryWorker.compensate(job([delivered, lost]), "boom")

      refute undelivered(delivered)
      assert undelivered(lost)
    end

    # A topic whose consumers were all removed from config since the event was staged.
    test "records nothing for an event that is no longer routed anywhere", ctx do
      route([], ctx)

      assert :ignore = EventDeliveryWorker.compensate(job([event("thing-1")]), "boom")
    end

    # The sweep can reach the same dead job twice; the unique index refuses the
    # duplicate rather than the compensation having to remember.
    test "does not duplicate a row when the same job is compensated twice", ctx do
      route([{Recorder, :first}], ctx)
      event = event("thing-1")
      job = job([event])

      assert :ok = EventDeliveryWorker.compensate(job, "boom")
      assert :ok = EventDeliveryWorker.compensate(job, "boom")

      assert [_one] = Repo.all(from(u in UndeliveredEvent, where: u.event_id == ^event.event_id))
    end
  end

  describe "replay/1" do
    # The stored payload IS what `args["events"]` carries, so replay hands it straight
    # back with no `deserialize/1` round-trip. That is not a shortcut: deserializing
    # calls `String.to_existing_atom/1`, so a replay of an event whose type was retired
    # since would raise inside the admin's click instead of re-delivering.
    test "enqueues a delivery job carrying the stored envelope", ctx do
      route([{Recorder, :first}], ctx)
      event = event("thing-1")
      row = dead_letter(event, ctx)

      assert :ok = replay(row)

      assert [job] = Repo.all(from(j in Oban.Job, where: j.worker == ^worker_name()))
      assert job.args["events"] == [EventSerializer.serialize(event)]
      assert job.args["replay_of"] == event.event_id
    end

    test "stamps the row so the prune can tell it from one nobody noticed", ctx do
      route([{Recorder, :first}], ctx)
      row = dead_letter(event("thing-1"), ctx)

      assert :ok = replay(row)

      assert undelivered(row).replayed_at
    end

    # `consumers_for/1` returns [] for an unrouted topic, so delivery would map over
    # nothing and report :ok — a green job that did nothing, which is worse than a
    # refusal because it looks like the recovery worked.
    test "refuses when a missed consumer is no longer routed, naming it", ctx do
      route([{Recorder, :first}], ctx)
      row = dead_letter(event("thing-1"), ctx)
      route([], ctx)

      assert {:error, {:retired_consumers, [ref]}} = replay(row)
      assert ref == handler_ref({Recorder, :first})
    end

    test "enqueues nothing and stamps nothing when it refuses", ctx do
      route([{Recorder, :first}], ctx)
      row = dead_letter(event("thing-1"), ctx)
      route([], ctx)

      assert {:error, _reason} = replay(row)

      assert [] = Repo.all(from(j in Oban.Job, where: j.worker == ^worker_name()))
      refute undelivered(row).replayed_at
    end

    # The whole premise of replay being cheap. `processed_events` gates each consumer,
    # so what is asserted is the state change — the recorder's calls — rather than the
    # gate's own bookkeeping, which would prove only that the gate was consulted.
    test "re-runs only the consumers that never succeeded", ctx do
      route([{Recorder, :first}, {Recorder, :second}], ctx)
      event = event("thing-1")
      mark_processed(event, {Recorder, :first})
      row = dead_letter(event, ctx)

      deliver_replay(row)

      assert [{:second, "thing-1"}] = Recorder.calls()
    end

    test "forgets the row once every missed consumer has landed", ctx do
      route([{Recorder, :first}], ctx)
      row = dead_letter(event("thing-1"), ctx)

      deliver_replay(row)

      refute undelivered(row)
    end

    test "keeps the row when a consumer fails again", ctx do
      route([{Recorder, :flaky}], ctx)
      row = dead_letter(event("thing-1"), ctx)

      capture_log(fn -> deliver_replay(row) end)

      assert undelivered(row)
    end

    # A replay stamp is never cleared, so a row that failed again is still replayable —
    # and the second stamp has to survive the re-recording the failure triggers.
    test "can be replayed again after a replay that failed", ctx do
      route([{Recorder, :flaky}], ctx)
      row = dead_letter(event("thing-1"), ctx)
      capture_log(fn -> deliver_replay(row) end)

      assert :ok = replay(undelivered(row))
    end
  end

  describe "queue wiring" do
    # Staging into a queue no producer is running for strands the job quietly — nothing
    # errors, the row simply sits — and a typo in the worker's `queue:` would do it to
    # every event at once.
    test "the queue this worker stages into is one that is actually configured" do
      queues = Application.get_env(:klass_hero, Oban)[:queues]
      staged_queue = EventDeliveryWorker.new(%{"events" => []}).changes.queue

      assert staged_queue == "events"
      assert Keyword.has_key?(queues, String.to_existing_atom(staged_queue))
    end
  end
end
