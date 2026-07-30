defmodule KlassHero.Shared.Adapters.Driven.Workers.EventDeliveryWorker do
  @moduledoc """
  Delivers one transaction's integration events to every consumer of each.

  Generalizes `CriticalEventWorker`, which carried one event to one handler. This
  carries N events to all their registered consumers — cross-context handlers and
  projections alike, because `EventConsumerRegistry` makes them the same kind of
  entry.

  ## Why the job invokes consumers rather than broadcasting to them

  A job that only broadcasts is durable up to the broadcast and no further: Oban
  marks it complete the instant the message is sent, so a consumer restarting at
  that moment loses the event with nothing left to retry it. Calling consumers
  directly means a consumer failure fails the job, and Oban's retry is the
  recovery. PubSub keeps only the LiveView broadcast, where a dropped refresh is
  the one loss this system is allowed to take.

  Each consumer runs through `CriticalEventDispatcher`, so at-least-once delivery
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
    queue: :critical_events,
    max_attempts: 10

  alias KlassHero.Shared.Adapters.Driven.Events.CriticalEventSerializer
  alias KlassHero.Shared.Adapters.Driven.Events.EventConsumerRegistry
  alias KlassHero.Shared.CriticalEventDispatcher
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.Tracing.Context

  require Logger

  @impl true
  def execute(%Oban.Job{args: %{"events" => raw_events}} = job) do
    raw_events
    |> Enum.map(&CriticalEventSerializer.deserialize/1)
    |> Enum.map(&deliver(&1, job))
    |> first_error()
  end

  # No broadcast: `integration:` topics have no subscribers. Projections stopped
  # subscribing in PR 3, and no LiveView ever did — those now receive tagged
  # tuples from whoever wrote the data they read.
  defp deliver(%IntegrationEvent{} = event, job) do
    Context.attach_from_event(event)
    topic = IntegrationEvent.topic(event)

    topic
    |> EventConsumerRegistry.consumers_for()
    |> Enum.map(&run_consumer(&1, event, topic, job))
    |> first_error()
  end

  defp run_consumer({module, function} = consumer, event, topic, job) do
    handler_ref = CriticalEventDispatcher.handler_ref(consumer)

    case CriticalEventDispatcher.execute(event.event_id, handler_ref, fn -> apply(module, function, [event]) end) do
      :ok ->
        :ok

      {:error, reason} = error ->
        log_consumer_failure(event, topic, handler_ref, reason, job)
        error
    end
  end

  # error once retries are exhausted (ErrorTracker alerts on it), warning while any remain.
  defp log_consumer_failure(event, topic, handler_ref, reason, %Oban.Job{attempt: attempt, max_attempts: max_attempts}) do
    metadata = [
      event_id: event.event_id,
      topic: topic,
      consumer: handler_ref,
      reason: inspect(reason),
      attempt: attempt,
      max_attempts: max_attempts
    ]

    if attempt >= max_attempts do
      Logger.error(
        "Event delivery permanently failed after #{max_attempts} attempts: #{topic} -> #{handler_ref}",
        metadata
      )
    else
      Logger.warning("Event delivery failed (attempt #{attempt}/#{max_attempts}): #{topic} -> #{handler_ref}", metadata)
    end
  end

  defp first_error(results), do: Enum.find(results, :ok, &match?({:error, _reason}, &1))
end
