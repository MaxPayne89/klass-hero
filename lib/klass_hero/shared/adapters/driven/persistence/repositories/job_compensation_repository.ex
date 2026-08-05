defmodule KlassHero.Shared.Adapters.Driven.Persistence.Repositories.JobCompensationRepository do
  @moduledoc """
  Exactly-once execution of a dead Oban job's compensating action.

  Same shape as `ProcessedEventRepository.execute_atomically/3`, for the same
  reason: the marker row and the work it describes commit together, so exactly-once
  is a unique constraint rather than careful code. A compensation that fails leaves
  no marker, and the next sweep retries it.

  That duplication is deliberate and was surveyed — see #1249 for why the two are not
  extracted into one gate, and what would justify extracting them.

  ## Why `:ignore` is not `{:error, _}`

  A compensation whose entity is already terminal — an invite already `:enrolled`,
  a reply already `:sent` — has nothing left to do. That is a success, and it must
  commit its marker. Returning `{:error, _}` there would roll the marker back and
  make the sweep re-attempt the same job on every tick until the Pruner deletes the
  `oban_jobs` row a week later. `{:error, _}` is reserved for a transient failure
  that a later sweep could genuinely fix.
  """

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.JobCompensation

  require Logger

  @doc """
  Runs `compensation_fn` at most once for `job_id`, recording that it ran.

  Returns `:ok` when the compensation ran (or was already recorded, or reported
  `:ignore`), and `{:error, reason}` when it failed — in which case no marker is
  left behind.
  """
  @spec compensate_once(integer(), String.t(), (-> :ok | :ignore | {:error, term()})) ::
          :ok | {:error, term()}
  def compensate_once(job_id, worker, compensation_fn)
      when is_integer(job_id) and is_binary(worker) and is_function(compensation_fn, 0) do
    db_interaction operation: :compensate_once, entity: "job_compensation" do
      Repo.transaction(fn ->
        case insert_marker(job_id, worker) do
          # Another sweep — or an earlier tick — already compensated this job.
          :already_compensated ->
            :ok

          # Runs inside the transaction so a rollback removes the marker with it.
          :inserted ->
            run_compensation(compensation_fn)
        end
      end)
      |> unwrap_transaction_result()
    end
  end

  @doc """
  Deletes markers compensated before `cutoff`, returning how many went.

  Cutting on `compensated_at` rather than the job's `discarded_at` is deliberate and
  safe in the conservative direction: a marker can only be written while the sweep's
  join still sees the `oban_jobs` row, so `compensated_at >= discarded_at` always, and
  a cutoff measured from it therefore lands no earlier than the same span measured
  from the job's own clock. The caller owns the span — see `CompensationSweepWorker`.
  """
  @spec prune(DateTime.t()) :: non_neg_integer()
  def prune(%DateTime{} = cutoff) do
    db_interaction operation: :prune, entity: "job_compensation" do
      {deleted, _returning} =
        Repo.delete_all(from(compensation in JobCompensation, where: compensation.compensated_at < ^cutoff))

      deleted
    end
  end

  # `insert_all` with `on_conflict: :nothing` rather than `Repo.insert`: the latter
  # raises `Ecto.ConstraintError` on a duplicate, which aborts the enclosing
  # transaction unless run at a savepoint (#1065). This never raises — a losing race
  # simply reports zero rows affected.
  defp insert_marker(job_id, worker) do
    row = %{job_id: job_id, worker: worker, compensated_at: DateTime.utc_now()}

    case Repo.insert_all(JobCompensation, [row], on_conflict: :nothing) do
      {1, _returning} -> :inserted
      {0, _returning} -> :already_compensated
    end
  end

  defp run_compensation(compensation_fn) do
    case compensation_fn.() do
      :ok -> :ok
      :ignore -> :ok
      {:error, reason} -> Repo.rollback({:compensation_failed, reason})
    end
  rescue
    error ->
      # Log before Repo.rollback, which loses the original stacktrace.
      Logger.error("Job compensation crashed: #{Exception.message(error)}",
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      Repo.rollback({:compensation_crashed, error})
  end

  defp unwrap_transaction_result({:ok, :ok}), do: :ok
  defp unwrap_transaction_result({:error, {:compensation_failed, reason}}), do: {:error, reason}

  defp unwrap_transaction_result({:error, {:compensation_crashed, error}}), do: {:error, {:compensation_crashed, error}}

  defp unwrap_transaction_result({:error, reason}), do: {:error, reason}
end
