# Helper module defined outside the test module to avoid import conflict between
# TracingHelpers.span (record accessor) and Tracing.span (macro).
defmodule TracedWorkerContextHelper do
  use KlassHero.Shared.Tracing

  alias KlassHero.Shared.Tracing.Context

  def inject_into_args_for_worker do
    span "TracedWorkerContextHelper.enqueue" do
      Context.inject_into_args(%{})
    end
  end
end

defmodule KlassHero.Shared.Tracing.TracedWorkerTest do
  use ExUnit.Case, async: false
  use KlassHero.TracingHelpers

  alias KlassHero.Shared.Tracing.TracedWorker

  # Span isolation (flush + drain between tests) is provided by the shared
  # `use KlassHero.TracingHelpers` setup.

  defp build_job(attrs \\ %{}) do
    defaults = %Oban.Job{
      args: %{},
      queue: "test",
      worker: "KlassHero.Shared.Tracing.TracedWorkerTest.SuccessWorker",
      attempt: 1,
      max_attempts: 3
    }

    struct(defaults, attrs)
  end

  # ---- Test workers defined inline ----

  defmodule SuccessWorker do
    use TracedWorker, queue: :test, max_attempts: 3

    @impl TracedWorker
    @spec execute(Oban.Job.t()) :: :ok | {:ok, term()} | {:error, term()}
    def execute(_job), do: :ok
  end

  defmodule FailWorker do
    use TracedWorker, queue: :test, max_attempts: 3

    @impl TracedWorker
    def execute(_job), do: {:error, "something went wrong"}
  end

  defmodule OkTupleWorker do
    use TracedWorker, queue: :test, max_attempts: 3

    @impl TracedWorker
    @spec execute(Oban.Job.t()) :: :ok | {:ok, term()} | {:error, term()}
    def execute(_job), do: {:ok, :some_result}
  end

  # ---- Tests ----

  describe "span creation and attributes on success" do
    test "creates a span named from the worker module" do
      job = build_job()
      SuccessWorker.perform(job)

      assert_span("Shared.Tracing.TracedWorkerTest.SuccessWorker.execute/1")
    end

    test "sets oban.queue attribute" do
      job = build_job(%{queue: "email"})
      SuccessWorker.perform(job)

      assert_span("Shared.Tracing.TracedWorkerTest.SuccessWorker.execute/1",
        "oban.queue": "email"
      )
    end

    test "sets oban.worker attribute to formatted module name" do
      job = build_job()
      SuccessWorker.perform(job)

      assert_span("Shared.Tracing.TracedWorkerTest.SuccessWorker.execute/1",
        "oban.worker": "Shared.Tracing.TracedWorkerTest.SuccessWorker"
      )
    end

    test "sets oban.attempt attribute" do
      job = build_job(%{attempt: 2})
      SuccessWorker.perform(job)

      assert_span("Shared.Tracing.TracedWorkerTest.SuccessWorker.execute/1",
        "oban.attempt": 2
      )
    end

    test "sets oban.max_attempts attribute" do
      job = build_job(%{max_attempts: 5})
      SuccessWorker.perform(job)

      assert_span("Shared.Tracing.TracedWorkerTest.SuccessWorker.execute/1",
        "oban.max_attempts": 5
      )
    end
  end

  describe "return values" do
    test "returns :ok for successful :ok execution" do
      job = build_job()
      assert :ok = SuccessWorker.perform(job)
    end

    test "returns {:ok, value} for {:ok, value} execution" do
      job = build_job()
      assert {:ok, :some_result} = OkTupleWorker.perform(job)
    end

    test "returns {:error, reason} for failed execution" do
      job = build_job()
      assert {:error, "something went wrong"} = FailWorker.perform(job)
    end
  end

  describe "trace context propagation" do
    test "propagates trace context from job args across process boundary" do
      # Use the Helpers module to create a parent span and inject context into args,
      # mirroring the pattern from ContextTest.
      enriched_args = TracedWorkerContextHelper.inject_into_args_for_worker()

      job = build_job(%{args: enriched_args})

      # Simulate the worker running in a separate process (as Oban does).
      # Re-register the exporter so spans from the child process reach this test.
      test_pid = self()

      task =
        Task.async(fn ->
          :otel_batch_processor.set_exporter(:otel_exporter_pid, test_pid)
          SuccessWorker.perform(job)
        end)

      Task.await(task)

      enqueue_span = assert_span("TracedWorkerContextHelper.enqueue")
      worker_span = assert_span("Shared.Tracing.TracedWorkerTest.SuccessWorker.execute/1")

      # Both spans should share the same trace_id, proving context was propagated
      assert span(enqueue_span, :trace_id) == span(worker_span, :trace_id),
             "Worker span should share the parent trace_id (context propagation)"
    end
  end

  describe "error handling and retry logic" do
    test "sets oban.will_retry to true when attempts remain" do
      # attempt=1, max_attempts=3 => will retry
      job = build_job(%{attempt: 1, max_attempts: 3})
      FailWorker.perform(job)

      assert_span("Shared.Tracing.TracedWorkerTest.FailWorker.execute/1",
        "oban.will_retry": true
      )
    end

    test "sets oban.will_retry to false on final attempt failure" do
      # attempt=3, max_attempts=3 => will NOT retry
      job = build_job(%{attempt: 3, max_attempts: 3})
      FailWorker.perform(job)

      assert_span("Shared.Tracing.TracedWorkerTest.FailWorker.execute/1",
        "oban.will_retry": false
      )
    end

    test "sets span status to error on failure" do
      job = build_job()
      FailWorker.perform(job)

      worker_span = assert_span("Shared.Tracing.TracedWorkerTest.FailWorker.execute/1")
      assert span_status_code(worker_span) == :error
    end

    test "does not set error status on success" do
      job = build_job()
      SuccessWorker.perform(job)

      worker_span = assert_span("Shared.Tracing.TracedWorkerTest.SuccessWorker.execute/1")

      # On success, status is either :unset or :ok — never :error
      raw_status = span(worker_span, :status)
      assert raw_status == :undefined or span_status_code(worker_span) != :error
    end
  end
end
