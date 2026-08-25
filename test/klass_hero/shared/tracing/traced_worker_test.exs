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
  # `async: false` for the OTel exporter, which is process-global. DataCase rather than
  # a bare ExUnit.Case because `compensate_if_final/3` writes a compensation marker.
  use KlassHero.DataCase, async: false
  use KlassHero.TracingHelpers

  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.JobCompensation
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

  # A real `id`, because the marker is keyed on it — every job reaching the gate in
  # production came out of `oban_jobs`. `job_compensations` has no foreign key back, so
  # the row need not exist.
  defp compensating_job(opts \\ []) do
    build_job(%{
      id: System.unique_integer([:positive]),
      worker: "KlassHero.Shared.Tracing.TracedWorkerTest.CompensatingWorker",
      attempt: Keyword.get(opts, :attempt, 3),
      max_attempts: 3,
      args: %{"test_pid" => self(), "returns" => Keyword.get(opts, :returns, :ok)}
    })
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

  defmodule CancelWorker do
    use TracedWorker, queue: :test, max_attempts: 3

    @impl TracedWorker
    def execute(_job), do: {:cancel, "nothing a retry can fix"}
  end

  # Reports that it ran before returning whatever the test asked for, so a compensation
  # that gets rolled back can still be distinguished from one that never happened.
  defmodule CompensatingWorker do
    use TracedWorker, queue: :test, max_attempts: 3

    @impl TracedWorker
    def execute(_job), do: {:error, :boom}

    @impl TracedWorker
    def compensate(%Oban.Job{args: %{"test_pid" => pid, "returns" => returns}}, reason) do
      send(pid, {:compensated, reason})
      returns
    end
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

    # A cancel is still a failure, just one no retry can fix. Before invite delivery
    # started cancelling, that path returned {:error, _} and marked its span — leaving
    # cancels unmarked would silently drop them out of every error-status query.
    test "sets span status to error on cancel" do
      job = build_job(%{attempt: 1, max_attempts: 3})
      CancelWorker.perform(job)

      worker_span = assert_span("Shared.Tracing.TracedWorkerTest.CancelWorker.execute/1")
      assert span_status_code(worker_span) == :error
    end

    test "reports a cancelled job as not retrying" do
      job = build_job(%{attempt: 1, max_attempts: 3})
      CancelWorker.perform(job)

      assert_span("Shared.Tracing.TracedWorkerTest.CancelWorker.execute/1",
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
      assert raw_status == :undefined
    end
  end

  # The in-attempt gate and the sweep both reach the same `compensate/2`, and the marker
  # is what keeps them from both running it. Before #1339 only the sweep wrote one, so
  # every inline-compensated job was also swept — harmless until the entity acquired a
  # legal path back out of the state the compensation had put it in.
  describe "compensate_if_final/3" do
    test "records the compensation, so the sweep will not repeat it" do
      job = compensating_job()

      assert :ok = TracedWorker.compensate_if_final(CompensatingWorker, job, :delivery_failed)

      assert_received {:compensated, :delivery_failed}
      assert Repo.get_by(JobCompensation, job_id: job.id)
    end

    test "runs the compensation once when the gate is reached twice" do
      job = compensating_job()

      assert :ok = TracedWorker.compensate_if_final(CompensatingWorker, job, :delivery_failed)
      assert :ok = TracedWorker.compensate_if_final(CompensatingWorker, job, :delivery_failed)

      assert_received {:compensated, :delivery_failed}
      refute_received {:compensated, _reason}
    end

    # The marker and the compensating write commit together, so a failure must leave
    # neither — otherwise the sweep skips a job whose compensation never landed.
    test "records nothing when the compensation fails, leaving the job to a later sweep" do
      job = compensating_job(returns: {:error, :database_gone})

      assert {:error, :database_gone} =
               TracedWorker.compensate_if_final(CompensatingWorker, job, :delivery_failed)

      assert_received {:compensated, :delivery_failed}
      refute Repo.get_by(JobCompensation, job_id: job.id)
    end

    # `:ignore` means "nothing left to do", which is a completed compensation, not a
    # failed one — it must commit its marker like any other success.
    test "records a compensation that reports nothing left to do" do
      job = compensating_job(returns: :ignore)

      assert :ok = TracedWorker.compensate_if_final(CompensatingWorker, job, :delivery_failed)

      assert Repo.get_by(JobCompensation, job_id: job.id)
    end

    test "neither compensates nor records while retries remain" do
      job = compensating_job(attempt: 1)

      assert :ok = TracedWorker.compensate_if_final(CompensatingWorker, job, :delivery_failed)

      refute_received {:compensated, _reason}
      refute Repo.get_by(JobCompensation, job_id: job.id)
    end
  end

  describe "final_attempt?/1" do
    # `>=`, not `==`: Lifeline re-runs a job orphaned by a node crash, so an
    # attempt can arrive already past the ceiling. Equality would read that as
    # "retries remain" and skip the compensation the caller is gating on.
    test "is true only once no attempts remain" do
      cases = [{1, 3, false}, {2, 3, false}, {3, 3, true}, {4, 3, true}]

      for {attempt, max_attempts, expected} <- cases do
        job = build_job(%{attempt: attempt, max_attempts: max_attempts})

        assert TracedWorker.final_attempt?(job) == expected,
               "attempt #{attempt} of #{max_attempts}: expected #{expected}"
      end
    end
  end
end
