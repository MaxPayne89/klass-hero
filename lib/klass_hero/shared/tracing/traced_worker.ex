defmodule KlassHero.Shared.Tracing.TracedWorker do
  @moduledoc """
  Macro module that replaces `use Oban.Worker` for workers that should be traced.

  ## Usage

      defmodule MyApp.Workers.MyWorker do
        use KlassHero.Shared.Tracing.TracedWorker, queue: :email, max_attempts: 3

        @impl KlassHero.Shared.Tracing.TracedWorker
        def execute(%Oban.Job{args: args}) do
          # ... do work
          :ok
        end
      end

  All options are passed through to `use Oban.Worker`. The macro generates a
  `perform/1` implementation that:

  1. Extracts and attaches trace context from `job.args["trace_context"]`
  2. Wraps `execute/1` in a span named from the worker module
  3. Sets standard `oban.*` attributes on the span
  4. Records retry status and error status on `{:error, _}` returns

  The `backoff/1` and `timeout/1` callbacks remain overridable by concrete workers.
  """

  alias KlassHero.Shared.Tracing

  @callback execute(Oban.Job.t()) :: :ok | {:ok, term()} | {:error, term()}

  @doc """
  Establishes the business fact that this job gave up permanently.

  Implement it when giving up has a consequence someone must see — an invite that
  has to show as `:failed`, an email that has to stop looking pending. The
  in-attempt `final_attempt?/1` gate calls it, and so does the sweep over
  discarded jobs, because a job can die without ever running the gate: Lifeline
  discards an orphan at the attempt ceiling without invoking `perform/1`, a raise
  bypasses the error branch the gate lives in, and an explicit `{:discard, _}` can
  return before the final attempt.

  Return `:ignore` — never `{:error, _}` — when there is nothing left to do,
  including when the entity is already terminal or no longer exists. `:ignore`
  records the compensation as done; `{:error, _}` rolls that record back and asks
  the next sweep to try again, so using it for a permanent condition re-runs the
  compensation every tick until the job row is pruned.

  `reason` is whatever the failing attempt returned, and `nil` when it cannot be
  known. Lifeline's discard writes no error at all, and for the other routes Oban
  stores `Exception.format/3` or `Oban.PerformError`'s message — formatted strings
  embedding `inspect/1` output, not the original term. Render it; never match on it.
  """
  @callback compensate(Oban.Job.t(), reason :: term() | nil) :: :ok | :ignore | {:error, term()}

  @optional_callbacks compensate: 2

  @doc """
  True once Oban has no retries left for this job.

  Workers gate compensating actions on this: a compensation applied while
  retries remain destroys the state the next attempt would have healed.

  `>=` rather than `==` because Lifeline re-runs a job orphaned by a node
  crash, so an attempt can arrive already past the ceiling.
  """
  @spec final_attempt?(Oban.Job.t()) :: boolean()
  def final_attempt?(%Oban.Job{attempt: attempt, max_attempts: max_attempts}) do
    attempt >= max_attempts
  end

  @doc """
  Compensates now if this is the last attempt, otherwise leaves it to a later one.

  The in-attempt fast path. A job that dies without reaching it — orphaned, raised,
  or discarded early — is caught later by the sweep over discarded jobs, which calls
  the same `compensate/2`.
  """
  @spec compensate_if_final(module(), Oban.Job.t(), term()) :: :ok | :ignore | {:error, term()}
  def compensate_if_final(worker, %Oban.Job{} = job, reason) when is_atom(worker) do
    if final_attempt?(job), do: worker.compensate(job, reason), else: :ok
  end

  @doc false
  @spec record_result(term(), Oban.Job.t()) :: :ok
  def record_result({:error, _reason}, %Oban.Job{} = job) do
    Tracing.set_attribute("oban.will_retry", not final_attempt?(job))
    OpenTelemetry.Tracer.set_status(:error, "job failed")
    :ok
  end

  # A cancel is a failure the worker knows no retry can fix, so it belongs in the same
  # error-status queries as a plain failure. Falling through to the no-op clause would
  # make a job that gave up look, in the trace, exactly like one that succeeded.
  def record_result({:cancel, _reason}, %Oban.Job{}) do
    Tracing.set_attribute("oban.will_retry", false)
    OpenTelemetry.Tracer.set_status(:error, "job cancelled")
    :ok
  end

  def record_result(_result, %Oban.Job{} = _job), do: :ok

  defmacro __using__(opts) do
    quote do
      @behaviour KlassHero.Shared.Tracing.TracedWorker

      use Oban.Worker, unquote(opts)
      use Tracing

      alias KlassHero.Shared.Tracing.Context
      alias KlassHero.Shared.Tracing.TracedWorker

      @impl Oban.Worker
      def perform(%Oban.Job{} = job) do
        # Attach trace context BEFORE creating any spans
        Context.attach_from_args(job.args)

        # credo:disable-for-next-line Credo.Check.Design.AliasUsage
        span_name = Tracing.gen_span_name_for_worker(__MODULE__)
        worker_name = String.replace_suffix(span_name, ".execute/1", "")

        tracer = :opentelemetry.get_application_tracer(__MODULE__)

        :otel_tracer.with_span(tracer, span_name, %{}, fn _ctx ->
          set_attribute("oban.queue", job.queue)
          set_attribute("oban.worker", worker_name)
          set_attribute("oban.attempt", job.attempt)
          set_attribute("oban.max_attempts", job.max_attempts)

          result =
            try do
              execute(job)
            rescue
              exception ->
                set_attribute("exception.type", inspect(exception.__struct__))
                set_attribute("exception.message", Exception.message(exception))

                set_attribute(
                  "exception.stacktrace",
                  Exception.format_stacktrace(__STACKTRACE__)
                )

                OpenTelemetry.Tracer.set_status(:error, "exception")
                reraise exception, __STACKTRACE__
            end

          TracedWorker.record_result(result, job)
          result
        end)
      end

      defoverridable perform: 1
    end
  end
end
