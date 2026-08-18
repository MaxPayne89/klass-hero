defmodule KlassHero.Shared.Adapters.Driven.Workers.EventDeliveryWorker do
  @moduledoc """
  Delivers one transaction's integration events to every consumer of each.

  Carries N events to all their registered consumers — cross-context handlers and
  projections alike, because `EventConsumerRegistry` makes them the same kind of
  entry. ADR-0014 replaced a per-event, per-handler worker with this one, which is
  why nothing downstream distinguishes a handler from a projection any more.

  ## Why the job invokes consumers rather than broadcasting to them

  A job that only broadcasts is durable up to the broadcast and no further: Oban
  marks it complete the instant the message is sent, so a consumer restarting at
  that moment loses the event with nothing left to retry it. Calling consumers
  directly means a consumer failure fails the job, and Oban's retry is the
  recovery. PubSub keeps only the LiveView broadcast, where a dropped refresh is
  the one loss this system is allowed to take.

  Each consumer runs through `EventDispatcher`, so at-least-once delivery
  does not become at-least-once *effects*: a consumer that already succeeded is a
  no-op on retry, and only the ones that failed run again.

  ## Ordering and failure

  Events are delivered in the order they were staged, which is the order the
  producer emitted them inline before this existed. Every event is attempted even
  if an earlier one failed — one poisoned event should not strand its siblings —
  and the first error is returned so Oban retries the whole job.
  """

  # Lifeline rescues an orphan only while `attempt < max_attempts` and discards it at the ceiling, so
  # this bound doubles as the window in which an orphaned event stays recoverable. 10 spans roughly
  # 4.5 hours under Oban's default backoff.
  use KlassHero.Shared.Tracing.TracedWorker,
    queue: :events,
    max_attempts: 10

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Events.EventConsumerRegistry
  alias KlassHero.Shared.Adapters.Driven.Events.EventSerializer
  alias KlassHero.Shared.Adapters.Driven.Persistence.Repositories.ProcessedEventRepository
  alias KlassHero.Shared.Adapters.Driven.Persistence.Repositories.UndeliveredEventRepository
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.UndeliveredEvent
  alias KlassHero.Shared.Domain.Events.Event
  alias KlassHero.Shared.EventDispatcher

  require Logger

  @impl true
  def execute(%Oban.Job{args: %{"events" => raw_events}} = job) do
    raw_events
    |> Enum.map(&EventSerializer.deserialize/1)
    |> Enum.map(&deliver(&1, job))
    |> first_error()
    |> resolve_replay(job)
  end

  # Only a replay carries `replay_of`, so an ordinary delivery pays one failed match.
  # `:ok` out of `first_error/1` already means every consumer of every event landed,
  # which for a replay's single event is exactly "nothing outstanding".
  #
  # A crash between the delivery and this delete leaves the row behind with its event
  # in fact delivered; the next replay is then a job whose consumers are all already
  # recorded, which returns `:ok` and lands back here. Self-healing, not a mechanism.
  defp resolve_replay(:ok, %Oban.Job{args: %{"replay_of" => event_id}}) when is_binary(event_id) do
    UndeliveredEventRepository.resolve(event_id)
  end

  defp resolve_replay(result, _job), do: result

  # No broadcast: `integration:` topics have no subscribers. Projections stopped
  # subscribing in PR 3, and no LiveView ever did — those now receive tagged
  # tuples from whoever wrote the data they read.
  defp deliver(%Event{} = event, job) do
    topic = Event.topic(event)

    topic
    |> EventConsumerRegistry.consumers_for()
    |> Enum.map(&run_consumer(&1, event, topic, job))
    |> first_error()
  end

  defp run_consumer({module, function} = consumer, event, topic, job) do
    handler_ref = EventDispatcher.handler_ref(consumer)

    case EventDispatcher.execute(event.event_id, handler_ref, fn -> apply(module, function, [event]) end) do
      :ok ->
        :ok

      {:error, reason} = error ->
        log_consumer_failure(event, topic, handler_ref, reason, job)
        error
    end
  end

  # error once retries are exhausted (ErrorTracker alerts on it), warning while any remain.
  defp log_consumer_failure(
         event,
         topic,
         handler_ref,
         reason,
         %Oban.Job{attempt: attempt, max_attempts: max_attempts} = job
       ) do
    metadata = [
      event_id: event.event_id,
      topic: topic,
      consumer: handler_ref,
      reason: inspect(reason),
      attempt: attempt,
      max_attempts: max_attempts
    ]

    if TracedWorker.final_attempt?(job) do
      Logger.error(
        "Event delivery permanently failed after #{max_attempts} attempts: #{topic} -> #{handler_ref}",
        metadata
      )
    else
      Logger.warning("Event delivery failed (attempt #{attempt}/#{max_attempts}): #{topic} -> #{handler_ref}", metadata)
    end
  end

  defp first_error(results), do: Enum.find(results, :ok, &match?({:error, _reason}, &1))

  @doc """
  Dead-letters whatever this job never managed to deliver.

  The fact established here is a negative one: these consumers did not react, and
  now never will. It is written by the sweep over discarded jobs rather than by
  the in-attempt gate, because the three routes that skip that gate — a Lifeline
  orphan, a raise, an early `{:discard, _}` — are exactly the ones a log line
  cannot see, and nothing user-facing is waiting on this row within the five
  minutes the sweep takes.

  The loss is partial. `processed_events` keeps the consumers that did run, so an
  event whose consumers all succeeded is recorded as nothing at all, and one that
  half-landed records only the half that did not.

  `missed_consumers` is resolved against the registry as it stands *now*, not as
  it stood when the event was staged: a consumer deleted from `:event_consumers`
  in between is not something anyone can still replay to.
  """
  @impl true
  def compensate(%Oban.Job{args: %{"events" => raw_events}} = job, _reason) do
    raw_events
    |> Enum.map(&EventSerializer.deserialize/1)
    |> Enum.flat_map(&undelivered_row(&1, job))
    |> record()
  end

  # `:ignore`, never `{:error, _}`: nothing was lost, and an error would roll back
  # the compensation marker and re-run this every sweep until the job row is pruned.
  defp record([]), do: :ignore
  defp record(rows), do: UndeliveredEventRepository.record_all(rows)

  defp undelivered_row(%Event{} = event, %Oban.Job{} = job) do
    topic = Event.topic(event)
    processed = ProcessedEventRepository.processed_handler_refs(event.event_id)

    case missed_consumers(topic, processed) do
      [] ->
        []

      missed ->
        [
          %{
            event_id: event.event_id,
            topic: topic,
            payload: EventSerializer.serialize(event),
            missed_consumers: missed,
            job_id: job.id,
            discarded_at: job.discarded_at,
            inserted_at: DateTime.utc_now()
          }
        ]
    end
  end

  # Registry order is delivery order, and it is kept: reading the row should tell you
  # which consumer was reached and which one the failure stopped at.
  defp missed_consumers(topic, processed) do
    delivered = MapSet.new(processed)

    for consumer <- EventConsumerRegistry.consumers_for(topic),
        ref = EventDispatcher.handler_ref(consumer),
        not MapSet.member?(delivered, ref),
        do: ref
  end

  @doc """
  Re-delivers a dead-lettered event to the consumers that never received it.

  The inverse of `compensate/2`, and deliberately in the same module: the job-args
  shape is this worker's, and building it anywhere else would give it a third knower.

  Callers outside Shared go through `KlassHero.Shared.EventReplay`, which is the
  root-level door to this; `adapters/` is Shared's internals.

  The stored `payload` is already `EventSerializer.serialize/1` output, so it goes
  straight back into `args` with no `deserialize/1` round-trip — which matters
  because deserializing calls `String.to_existing_atom/1`, and an event whose type
  was retired since would raise here rather than in the queue.

  Nothing has to be undone first. `EventDispatcher` gates each consumer on
  `processed_events`, so re-delivery re-runs only the ones with no row.

  ## A retired consumer is refused rather than replayed

  `consumers_for/1` returns `[]` for a topic nothing routes any more, so delivering
  to one would map over nothing and report success — a green job that did nothing.
  That is worse than a failure, because it reads as a recovery that worked, so a
  missed consumer no longer in `:event_consumers` refuses the whole replay.

  The enqueue and the stamp share one transaction. Oban's table is this database, so
  that is available for free, and without it a crash between them leaves a row
  claiming a replay that nothing is running.
  """
  @spec replay(UndeliveredEvent.t()) :: :ok | {:error, {:retired_consumers, [String.t()]}}
  def replay(%UndeliveredEvent{} = row) do
    case retired_consumers(row) do
      [] -> enqueue_replay(row)
      retired -> {:error, {:retired_consumers, retired}}
    end
  end

  defp retired_consumers(%UndeliveredEvent{topic: topic, missed_consumers: missed}) do
    routed = for consumer <- EventConsumerRegistry.consumers_for(topic), do: EventDispatcher.handler_ref(consumer)

    missed -- routed
  end

  defp enqueue_replay(%UndeliveredEvent{} = row) do
    args = Context.inject_into_args(%{"events" => [row.payload], "replay_of" => row.event_id})

    {:ok, :ok} =
      Repo.transaction(fn ->
        Oban.insert!(new(args))
        UndeliveredEventRepository.mark_replayed(row.event_id)
      end)

    :ok
  end
end
