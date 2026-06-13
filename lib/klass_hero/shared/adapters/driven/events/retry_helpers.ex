defmodule KlassHero.Shared.Adapters.Driven.Events.RetryHelpers do
  @moduledoc """
  Shared retry logic with error classification for event-driven operations.

  Retryable: `:database_connection_error`.
  Permanent (no retry): `:duplicate_resource` (treated as `:ok`), `:resource_not_found`,
  `:database_query_error`, `:database_unavailable`, `{:validation_error, _}`.
  Step-tagged errors like `{:step_name, reason}` delegate classification to the inner reason.
  """

  require Logger

  @default_backoff_ms 100

  @doc """
  Executes `operation` with one retry on transient errors and error classification.

  `context` must contain `:operation_name` and `:aggregate_id` (for logging) and
  may contain `:backoff_ms` (default 100). `:duplicate_resource` errors are treated
  as idempotent success. Permanent errors return immediately without retry.
  """
  @spec retry_with_backoff(
          operation :: (-> :ok | {:ok, term()} | {:error, atom() | {atom(), term()}}),
          context :: map()
        ) :: :ok | {:ok, term()} | {:error, atom() | {atom(), term()}}
  def retry_with_backoff(operation, context) when is_function(operation, 0) and is_map(context) do
    case normalize_result(operation.(), context) do
      {:success, result} ->
        result

      {:error, reason, error} ->
        maybe_retry(operation, context, reason, error)
    end
  end

  @doc """
  Like `retry_with_backoff/2` but normalizes `{:ok, _}` to bare `:ok`.

  Use when the operation returns `{:ok, result}` but the caller needs bare `:ok`.
  Typical for event handler contracts (ForHandlingEvents, ForHandlingIntegrationEvents)
  where handlers manage `:ignore` returns separately.
  """
  @spec retry_and_normalize(
          operation :: (-> :ok | {:ok, term()} | {:error, atom() | {atom(), term()}}),
          context :: map()
        ) :: :ok | {:error, atom() | {atom(), term()}}
  def retry_and_normalize(operation, context) when is_function(operation, 0) and is_map(context) do
    case retry_with_backoff(operation, context) do
      {:ok, _} -> :ok
      other -> other
    end
  end

  defp maybe_retry(operation, context, reason, error) do
    if retryable_error?(reason) do
      backoff_ms = Map.get(context, :backoff_ms, @default_backoff_ms)
      log_retry_attempt(reason, context)
      Process.sleep(backoff_ms)
      handle_retry(operation, context, error)
    else
      log_permanent_error(reason, context)
      error
    end
  end

  defp handle_retry(operation, context, original_error) do
    case normalize_result(operation.(), context) do
      {:success, result} ->
        log_retry_success(context)
        result

      {:error, _reason, _error} ->
        log_retry_failure(context)
        original_error
    end
  end

  # :duplicate_resource is treated as idempotent success.
  defp normalize_result(:ok, _context), do: {:success, :ok}
  defp normalize_result({:ok, result}, _context), do: {:success, {:ok, result}}

  defp normalize_result({:error, :duplicate_resource} = _error, context) do
    log_duplicate_resource(context)
    {:success, :ok}
  end

  defp normalize_result({:error, reason} = error, _context) do
    {:error, reason, error}
  end

  @doc """
  Determines if an error is transient and should be retried.

  Only database connection errors are considered transient and worth retrying.
  """
  @spec retryable_error?(atom() | {atom(), term()} | {atom(), atom() | {atom(), term()}}) ::
          boolean()
  def retryable_error?(:database_connection_error), do: true
  # Use case step-tagged errors like {:anonymize_messages, :database_connection_error} — classify the inner reason.
  def retryable_error?({_step, reason}) when is_atom(reason), do: retryable_error?(reason)
  def retryable_error?(_), do: false

  @doc """
  Determines if an error is permanent and should not be retried.
  """
  @spec permanent_error?(atom() | {atom(), term()} | {atom(), atom() | {atom(), term()}}) ::
          boolean()
  def permanent_error?(:duplicate_resource), do: true
  def permanent_error?(:resource_not_found), do: true
  def permanent_error?(:database_query_error), do: true
  def permanent_error?(:database_unavailable), do: true
  def permanent_error?({:validation_error, _}), do: true
  # Step-tagged errors (not :validation_error, already matched above) — classify the inner reason.
  def permanent_error?({step, reason}) when is_atom(step) and step != :validation_error, do: permanent_error?(reason)

  def permanent_error?(_), do: false

  defp log_retry_attempt(reason, context) do
    error_id = generate_error_id()

    Logger.warning(
      "[#{error_id}] [RetryHelpers] Retrying #{context.operation_name} " <>
        "for aggregate #{context.aggregate_id} after transient error: #{inspect(reason)}"
    )
  end

  defp log_retry_success(context) do
    Logger.info(
      "[RetryHelpers] Successfully #{context.operation_name} " <>
        "for aggregate #{context.aggregate_id} on retry"
    )
  end

  defp log_retry_failure(context) do
    error_id = generate_error_id()

    Logger.error(
      "[#{error_id}] [RetryHelpers] Failed to #{context.operation_name} " <>
        "for aggregate #{context.aggregate_id} after retry"
    )
  end

  defp log_permanent_error(reason, context) do
    error_id = generate_error_id()

    Logger.error(
      "[#{error_id}] [RetryHelpers] Permanent error during #{context.operation_name} " <>
        "for aggregate #{context.aggregate_id}: #{inspect(reason)} (no retry)"
    )
  end

  defp log_duplicate_resource(context) do
    Logger.debug(
      "[RetryHelpers] #{context.operation_name} for aggregate #{context.aggregate_id}: " <>
        "duplicate resource (idempotent - treated as success)"
    )
  end

  defp generate_error_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end
end
