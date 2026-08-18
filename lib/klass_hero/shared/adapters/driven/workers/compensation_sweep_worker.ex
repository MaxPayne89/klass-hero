defmodule KlassHero.Shared.Adapters.Driven.Workers.CompensationSweepWorker do
  @moduledoc """
  Establishes the compensating fact for jobs that died without running their gate.

  Workers compensate inline when Oban tells them the attempt is the last one. Three
  routes reach a terminal job without that branch ever evaluating:

    * `Oban.Plugins.Lifeline` discards an orphan left `executing` by a machine that
      went away. Its rescue is a bare `update_all`, so `perform/1` is never invoked.
    * A raised exception bypasses the `{:error, _}` branch the gate lives in, and
      lands the job in `discarded` once attempts are spent.
    * An explicit `{:discard, _}` return gives up before the final attempt.

  All three converge on `oban_jobs.state == "discarded"`, which is what this sweeps.
  The job row is the only durable trace — Lifeline's telemetry carries ids and
  nothing else — so reconciliation reads the table rather than listening for events.

  `cancelled` is deliberately **not** swept. A cancel is a decision the worker made,
  not a death it failed to observe, and re-deciding it here would override the one
  branch that had the context to judge. The obligation that falls out: a worker
  returning `{:cancel, _}` after a compensating write of its own must resolve that
  write itself, because nothing downstream will. `SendInviteEmailWorker`'s tokenless
  branch is the only such site — it returns `{:error, _}` when its write fails, so the
  retry machinery and then this sweep still apply (#1248).

  Scope is the `CompensatingWorkerRegistry` list, filtered in SQL. Without that, a
  discarded job from a worker that never compensates would be re-examined on every
  tick for as long as the Pruner keeps its row.
  """

  # `unique` because the schedule can outpace the run: Cron inserts on the leader only,
  # so nodes do not double-fire, but a sweep still executing when the next tick arrives
  # would otherwise be joined by a second one racing it over the same rows. `:incomplete`
  # rather than a hand-written state list, which silently omits `:suspended`/`:retryable`
  # and lets a duplicate through exactly when the previous run is in trouble.
  use KlassHero.Shared.Tracing.TracedWorker,
    queue: :cleanup,
    max_attempts: 3,
    unique: [period: 300, states: Oban.Job.unique_states(:incomplete)]

  import Ecto.Query

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.Repositories.JobCompensationRepository
  alias KlassHero.Shared.Adapters.Driven.Persistence.Repositories.UndeliveredEventRepository
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.JobCompensation
  alias KlassHero.Shared.CompensatingWorkerRegistry

  require Logger

  # Bounds one tick's work. Reaching it is reported rather than swallowed: a saturated
  # batch means the backlog is growing faster than the schedule drains it.
  @batch_limit 500

  # Dead-lettered events keep whatever personal data their payload carried, so they
  # expire on a rule rather than on nobody getting round to it. Long enough that any
  # realistic "what did we lose?" investigation still finds the payload.
  @undelivered_retention_days 90

  # A record nobody has replayed is the only trace of a reaction that never ran, and
  # this is the window where deleting it destroys the payload the recovery needs before
  # anyone has looked at it. So the ordinary retention above skips such a row — and this
  # is what stops "skipped" turning into "kept forever", which would be a personal-data
  # hold rather than a retention rule.
  @undelivered_backstop_days 365

  # A marker carries no personal data; it only has to outlive the `oban_jobs` row it guards,
  # which the Pruner deletes at 7 days. Everything past that is margin for the Pruner running
  # behind — it prunes only while a node is up, and 10_000 rows at a time. Shortening this
  # below the Pruner window deletes a marker whose job is still discardable and hands the same
  # job back to the sweep for a second compensation; `KlassHero.ObanConfigTest` is what stops
  # that going unnoticed.
  @job_compensation_retention_days 14

  @doc """
  How long a compensation marker is kept, in days.

  Public because the coupling to `Oban.Plugins.Pruner`'s window is asserted in
  `KlassHero.ObanConfigTest`, which reads config rather than module attributes.
  """
  @spec job_compensation_retention_days() :: pos_integer()
  def job_compensation_retention_days, do: @job_compensation_retention_days

  @impl true
  def execute(%Oban.Job{}) do
    pending = uncompensated_jobs()

    if length(pending) == @batch_limit do
      Logger.warning("Compensation sweep filled its batch; #{@batch_limit} jobs handled, more may remain")
    end

    Enum.each(pending, &compensate_job/1)
    prune_undelivered_events()
    prune_job_compensations()
    :ok
  end

  # Both prunes ride the 5-minute tick rather than a cron of their own: an indexed delete
  # over a table that is empty in the healthy case costs nothing, and the alternative is a
  # second schedule to keep in agreement with this one.
  defp prune_undelivered_events do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -@undelivered_retention_days, :day)
    backstop = DateTime.add(now, -@undelivered_backstop_days, :day)

    report_held(UndeliveredEventRepository.count_held(cutoff, backstop))

    case UndeliveredEventRepository.prune(cutoff, backstop) do
      0 -> :ok
      pruned -> Logger.info("Pruned #{pruned} undelivered event(s) past #{@undelivered_retention_days} days")
    end
  end

  # Counted before it is spared, because the alternative is a backlog that only ever
  # shows up when someone opens the admin page — which is the failure the exemption
  # exists to prevent, not one it should quietly extend.
  defp report_held(0), do: :ok

  defp report_held(held) do
    Logger.warning(
      "Holding #{held} unreplayed undelivered event(s) past #{@undelivered_retention_days} days; " <>
        "they are deleted at #{@undelivered_backstop_days} days whether replayed or not"
    )
  end

  # After the compensation pass, not before: pruning first could delete a marker and hand
  # its job straight back to `uncompensated_jobs/0` in the same tick.
  defp prune_job_compensations do
    cutoff = DateTime.add(DateTime.utc_now(), -@job_compensation_retention_days, :day)

    case JobCompensationRepository.prune(cutoff) do
      0 -> :ok
      pruned -> Logger.info("Pruned #{pruned} compensation marker(s) past #{@job_compensation_retention_days} days")
    end
  end

  defp uncompensated_jobs do
    names = CompensatingWorkerRegistry.worker_names()

    Repo.all(
      from(job in Oban.Job,
        left_join: compensation in JobCompensation,
        on: compensation.job_id == job.id,
        where: job.state == "discarded",
        where: job.worker in ^names,
        where: is_nil(compensation.job_id),
        order_by: [asc: job.discarded_at],
        limit: @batch_limit,
        select: job
      )
    )
  end

  defp compensate_job(%Oban.Job{} = job) do
    case Oban.Worker.from_string(job.worker) do
      {:ok, worker} ->
        run(worker, job)

      # Registered under a name nothing answers to any more — a worker renamed or deleted
      # while its dead jobs were still on the table. Nothing to compensate with, and no
      # marker written, so it resurfaces if the module comes back.
      {:error, error} ->
        Logger.error("Compensation sweep cannot resolve worker #{job.worker}: #{Exception.message(error)}")
    end
  end

  defp run(worker, %Oban.Job{} = job) do
    case JobCompensationRepository.compensate_once(job.id, job.worker, fn ->
           worker.compensate(job, reason_from(job))
         end) do
      :ok ->
        :ok

      # Left uncompensated on purpose: no marker was written, so the next tick retries.
      {:error, reason} ->
        Logger.error("Compensation failed for #{job.worker} job #{job.id}: #{inspect(reason)}")
    end
  end

  @doc """
  Best-effort cause of death, or `nil` when none was recorded.

  `oban_jobs.errors` holds maps of `%{"attempt" => _, "at" => _, "error" => _}`, and
  that `"error"` is already-formatted text — `Exception.format/3` for a raise, or
  `Oban.PerformError`'s `"... failed with \#{inspect(reason)}"` for a returned tuple.
  The original term is gone by the time it lands here, so this is for rendering only.

  A Lifeline discard appends nothing at all, so an orphan yields `nil`.
  """
  @spec reason_from(Oban.Job.t()) :: String.t() | nil
  def reason_from(%Oban.Job{errors: errors}) when is_list(errors) do
    case List.last(errors) do
      %{"error" => error} when is_binary(error) -> error
      _none -> nil
    end
  end

  def reason_from(%Oban.Job{}), do: nil
end
