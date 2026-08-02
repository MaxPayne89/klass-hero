defmodule KlassHero.Shared.Adapters.Driven.Persistence.Repositories.JobCompensationRepositoryTest do
  @moduledoc """
  The exactly-once gate for compensating a permanently-dead Oban job.

  The distinction that matters here is `:ignore` vs `{:error, _}`. A compensation
  whose entity is already terminal (invite already `:enrolled`, reply already
  `:sent`) has nothing left to do and must commit its marker — returning an error
  there would roll the marker back and make the sweep re-attempt that job on every
  tick until the Pruner deletes the row a week later.
  """

  use KlassHero.DataCase, async: true

  import ExUnit.CaptureLog

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.Repositories.JobCompensationRepository
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.JobCompensation

  @worker "KlassHero.Family.Adapters.Driving.Workers.ProcessInviteClaimWorker"

  describe "compensate_once/3" do
    test "runs the compensation and records it" do
      job_id = job_id()
      test_pid = self()

      result =
        JobCompensationRepository.compensate_once(job_id, @worker, fn ->
          send(test_pid, :compensated)
          :ok
        end)

      assert result == :ok
      assert_received :compensated
      assert %JobCompensation{worker: @worker} = Repo.get_by(JobCompensation, job_id: job_id)
    end

    test "does not run the compensation a second time" do
      job_id = job_id()
      test_pid = self()

      :ok = JobCompensationRepository.compensate_once(job_id, @worker, fn -> send(test_pid, :first) && :ok end)
      assert_received :first

      assert :ok =
               JobCompensationRepository.compensate_once(job_id, @worker, fn -> send(test_pid, :second) && :ok end)

      refute_received :second
    end

    # "Already terminal, nothing to do" is a success. The marker must persist so the
    # sweep stops reconsidering this job.
    test "records the marker when the compensation returns :ignore" do
      job_id = job_id()

      assert :ok = JobCompensationRepository.compensate_once(job_id, @worker, fn -> :ignore end)
      assert Repo.get_by(JobCompensation, job_id: job_id)
    end

    # A transient failure must leave no marker, so the next sweep tries again.
    test "rolls the marker back when the compensation fails" do
      job_id = job_id()

      assert {:error, :database_unavailable} =
               JobCompensationRepository.compensate_once(job_id, @worker, fn ->
                 {:error, :database_unavailable}
               end)

      refute Repo.get_by(JobCompensation, job_id: job_id)
    end

    test "rolls the marker back and logs when the compensation crashes" do
      job_id = job_id()

      log =
        capture_log([level: :error], fn ->
          JobCompensationRepository.compensate_once(job_id, @worker, fn -> raise "kaboom" end)
        end)

      assert log =~ "Job compensation crashed"
      assert log =~ "kaboom"
      refute Repo.get_by(JobCompensation, job_id: job_id)
    end

    test "a rolled-back compensation can be retried later" do
      job_id = job_id()

      assert {:error, :transient} =
               JobCompensationRepository.compensate_once(job_id, @worker, fn -> {:error, :transient} end)

      assert :ok = JobCompensationRepository.compensate_once(job_id, @worker, fn -> :ok end)
      assert Repo.get_by(JobCompensation, job_id: job_id)
    end
  end

  # oban_jobs ids are bigserial; these rows are never joined so any distinct integer works.
  defp job_id, do: System.unique_integer([:positive])
end
