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

  # A row staged before #1326: its metadata still carries `"criticality"`. No module
  # holds that atom any more, so a serializer that atomized whatever arrived would
  # raise on this — here, and again in `compensate/2`, losing the event with no
  # `undelivered_events` row to find it by. Both routes are covered because the
  # second is the one nothing else would have caught.
  defp legacy_job(events) do
    job = job(events)
    staged = Enum.map(job.args["events"], &Map.put(&1, "metadata", %{"criticality" => "critical"}))

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

  defp undelivered(event) do
    Repo.get_by(UndeliveredEvent, event_id: event.event_id)
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

  # #1357 moved this worker from `:critical_events` to `:events`. A queue rename is not a
  # rename: `oban_jobs.queue` is data, so every row staged before the deploy still says
  # "critical_events" — including anything mid-retry across the ~4.5h ladder. Both halves
  # of why those rows are still safe are pinned here, because they are different facts and
  # only one of them is behaviour.
  describe "the legacy :critical_events queue" do
    test "still executes its rows, because the worker column is what resolves the module", ctx do
      route([{Recorder, :first}], ctx)

      # `:manual` because `testing: :inline` would run the job at insert and never consult
      # the queue at all, which is the one thing this test is here to exercise.
      Oban.Testing.with_testing_mode(:manual, fn ->
        Oban.insert!(
          EventDeliveryWorker.new(%{"events" => [EventSerializer.serialize(event("thing-1"))]},
            queue: :critical_events
          )
        )

        Oban.drain_queue(queue: :critical_events, with_recursion: true)
      end)

      assert [{:first, "thing-1"}] = Recorder.calls()
    end

    # `drain_queue/2` above executes by queue name in the calling process and never consults
    # the `queues:` list, so it proves the code path and NOT that anything drains this queue
    # in production. That guarantee is a config fact, and this is the only thing asserting it.
    test "stays configured, or every row staged before #1357 is stranded" do
      queues = Application.get_env(:klass_hero, Oban)[:queues]

      assert Keyword.has_key?(queues, :critical_events),
             "dropping :critical_events strands every job staged before #1357 — confirm " <>
               "`SELECT count(*) FROM oban_jobs WHERE queue = 'critical_events'` is 0 in prod " <>
               "first. That is #1362, which removes this test along with the queue entry."
    end

    # The same failure from the other end: staging into a queue no producer is running for
    # strands the job just as quietly, and a typo in the worker's `queue:` would do it to
    # every event at once.
    test "the queue this worker now stages into is one that is actually configured" do
      queues = Application.get_env(:klass_hero, Oban)[:queues]
      staged_queue = EventDeliveryWorker.new(%{"events" => []}).changes.queue

      assert staged_queue == "events"
      assert Keyword.has_key?(queues, String.to_existing_atom(staged_queue))
    end
  end
end
