defmodule KlassHero.Shared.EventDispatchHelper do
  @moduledoc """
  Fire-and-forget event dispatch with criticality-aware logging and
  durable delivery for critical events.

  Wraps `DomainEventBus.dispatch/2` so callers never need to handle
  dispatch failures — the helper logs at the appropriate level based
  on event criticality and always returns `:ok`.

  For critical events, failed handlers are automatically retried via Oban.
  """

  alias KlassHero.Shared.CriticalEventDispatcher
  alias KlassHero.Shared.Domain.Events.EventMetadata
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.DomainEventBus

  require Logger

  @doc """
  Dispatches a domain event and logs failures at the appropriate level.

  For critical events:
  - Uses `DomainEventBus.dispatch_critical/2` to get per-handler results
  - Marks successful handlers as processed (idempotency gate)
  - Enqueues Oban retry jobs for failed handlers

  For normal events:
  - Uses `DomainEventBus.dispatch/2` (fire-and-forget, unchanged)

  Always returns `:ok` — dispatch failures never propagate to callers.

  Argument order is event-first for clean piping:

      AccountsEvents.user_registered(user)
      |> EventDispatchHelper.dispatch(KlassHero.Accounts)
  """
  @spec dispatch(IntegrationEvent.t(), module()) :: :ok
  def dispatch(%IntegrationEvent{} = event, context) do
    if EventMetadata.critical?(event) do
      dispatch_critical(event, context)
    else
      dispatch_normal(event, context)
    end
  end

  @doc """
  Dispatches a domain event and propagates the first handler failure.

  Unlike `dispatch/2` (fire-and-forget), this variant returns `{:error, reason}`
  when any handler fails — useful in `with` chains where dispatch failure must
  halt the pipeline.

  For critical events, this does NOT enqueue Oban jobs or mark handlers as
  processed. The caller owns error handling — they receive `{:error, reason}`
  and can roll back their own transaction. Enqueueing a retry or writing a
  processed_events row would conflict with the caller's rollback.

      FamilyEvents.invite_family_ready(invite_id, payload)
      |> EventDispatchHelper.dispatch_or_error(KlassHero.Family)
  """
  @spec dispatch_or_error(IntegrationEvent.t(), module()) :: :ok | {:error, term()}
  def dispatch_or_error(%IntegrationEvent{} = event, context) do
    if EventMetadata.critical?(event) do
      {:ok, results} = DomainEventBus.dispatch_critical(context, event)
      find_first_failure(results)
    else
      case DomainEventBus.dispatch(context, event) do
        :ok -> :ok
        {:error, [first_failure | _]} -> normalize_failure(first_failure)
      end
    end
  end

  @doc """
  Like `dispatch_or_error/2`, but on success returns `{:ok, value}` instead of
  bare `:ok`, keeping `with` chains uniform.

      reset.provider_id
      |> EnrollmentEvents.invite_resend_requested(reset.id, reset.program_id)
      |> EventDispatchHelper.dispatch_or_ok(KlassHero.Enrollment, reset)
  """
  @spec dispatch_or_ok(IntegrationEvent.t(), module(), value) :: {:ok, value} | {:error, term()}
        when value: term()
  def dispatch_or_ok(event, context, value) do
    case dispatch_or_error(event, context) do
      :ok -> {:ok, value}
      {:error, _} = error -> error
    end
  end

  defp find_first_failure(results) do
    case Enum.find(results, fn {_identity, result} -> match?({:error, _}, result) end) do
      nil -> :ok
      {_identity, {:error, reason}} -> {:error, reason}
    end
  end

  # Critical events: successful handlers are marked processed; failed handlers get Oban retry.
  defp dispatch_critical(event, context) do
    {:ok, results} = DomainEventBus.dispatch_critical(context, event)

    Enum.each(results, fn
      {identity, :ok} when identity != :anonymous ->
        ref = CriticalEventDispatcher.handler_ref(identity)
        CriticalEventDispatcher.mark_processed(event.event_id, ref)

      {identity, {:error, _reason}} when identity != :anonymous ->
        enqueue_critical_retry(event, identity)

      # Anonymous lambdas can't be serialized for Oban — log and skip.
      {_identity, {:error, _} = failure} ->
        log_dispatch_failure(event, [failure])

      _ ->
        :ok
    end)

    :ok
  end

  defp dispatch_normal(event, context) do
    case DomainEventBus.dispatch(context, event) do
      :ok ->
        :ok

      {:error, failures} ->
        log_dispatch_failure(event, failures)
        :ok
    end
  end

  defp enqueue_critical_retry(event, {_module, _function} = identity) do
    case CriticalEventDispatcher.enqueue_retry(event, identity) do
      :ok ->
        :ok

      {:error, reason} ->
        handler_ref = CriticalEventDispatcher.handler_ref(identity)

        Logger.error(
          "Failed to enqueue critical event retry: event_type=#{event.event_type} handler=#{handler_ref}",
          event_id: event.event_id,
          handler_ref: handler_ref,
          reason: inspect(reason)
        )
    end
  end

  defp log_dispatch_failure(event, failures) do
    if EventMetadata.critical?(event) do
      Logger.error("Critical event dispatch failed: event_type=#{event.event_type} failures=#{inspect(failures)}")
    else
      Logger.warning("Event dispatch failed: event_type=#{event.event_type} failures=#{inspect(failures)}")
    end
  end

  # Bus can produce {:error, reason}, {:error, {:handler_crashed, e}}, or bare terms.
  defp normalize_failure({:error, reason}), do: {:error, reason}
  defp normalize_failure(other), do: {:error, other}
end
