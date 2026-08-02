defmodule KlassHero.Shared.Adapters.Driven.Workers.CompensationSweepWorkerTest do
  @moduledoc """
  The three routes to a terminal job that never runs its own compensation gate all
  end in the same place — an `oban_jobs` row in `discarded` — so they are exercised
  here by writing that row directly rather than by staging a node failure.

  `Oban.insert/1` cannot produce them: the suite runs `testing: :inline`, which
  executes a job at insert and never lets one sit `executing` for Lifeline to find.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.Messaging
  alias KlassHero.MessagingFixtures
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.JobCompensation
  alias KlassHero.Shared.Adapters.Driven.Workers.CompensationSweepWorker

  @registered "KlassHero.Messaging.Adapters.Driving.Workers.SendEmailReplyWorker"
  @unregistered "KlassHero.Messaging.Adapters.Driving.Workers.MessageCleanupWorker"

  describe "execute/1" do
    test "compensates a discarded job and records that it did" do
      reply = pending_reply()
      job = discarded_job(@registered, %{"reply_id" => reply.id})

      assert :ok = CompensationSweepWorker.perform(%Oban.Job{})

      assert reply_status(reply) == :failed
      assert Repo.get_by(JobCompensation, job_id: job.id)
    end

    # A Lifeline discard records no error at all, so the compensation runs with no cause
    # to render. It must still establish the fact.
    test "compensates an orphan discarded with no recorded error" do
      reply = pending_reply()
      discarded_job(@registered, %{"reply_id" => reply.id}, errors: [])

      assert :ok = CompensationSweepWorker.perform(%Oban.Job{})
      assert reply_status(reply) == :failed
    end

    test "does not compensate the same job twice" do
      reply = pending_reply()
      discarded_job(@registered, %{"reply_id" => reply.id})

      assert :ok = CompensationSweepWorker.perform(%Oban.Job{})
      assert reply_status(reply) == :failed

      # A second reply delivered in the meantime proves the sweep re-ran at all; the
      # first must not be touched again.
      {:ok, _} = Messaging.update_email_reply_status(reply.id, "sending", %{})

      assert :ok = CompensationSweepWorker.perform(%Oban.Job{})
      assert reply_status(reply) == :sending
    end

    test "leaves jobs from unregistered workers alone" do
      reply = pending_reply()
      job = discarded_job(@unregistered, %{"reply_id" => reply.id})

      assert :ok = CompensationSweepWorker.perform(%Oban.Job{})

      assert reply_status(reply) == :sending
      refute Repo.get_by(JobCompensation, job_id: job.id)
    end

    # Only `discarded` means "dead". A cancelled job was given up on deliberately by code
    # that already handled it, and a retryable one still has attempts left.
    for state <- ~w(completed cancelled retryable available) do
      test "leaves #{state} jobs alone" do
        reply = pending_reply()
        job = discarded_job(@registered, %{"reply_id" => reply.id}, state: unquote(state))

        assert :ok = CompensationSweepWorker.perform(%Oban.Job{})

        assert reply_status(reply) == :sending, "expected a #{unquote(state)} job to be left alone"
        refute Repo.get_by(JobCompensation, job_id: job.id)
      end
    end

    test "compensates the remaining jobs when one of them is unresolvable" do
      reply = pending_reply()
      discarded_job("KlassHero.Workers.DeletedLongAgo", %{"reply_id" => reply.id})
      discarded_job(@registered, %{"reply_id" => reply.id})

      assert :ok = CompensationSweepWorker.perform(%Oban.Job{})
      assert reply_status(reply) == :failed
    end
  end

  describe "reason_from/1" do
    test "returns the last recorded error string" do
      job = %Oban.Job{
        errors: [
          %{"attempt" => 1, "error" => "** (RuntimeError) first"},
          %{"attempt" => 2, "error" => "** (RuntimeError) last"}
        ]
      }

      assert CompensationSweepWorker.reason_from(job) == "** (RuntimeError) last"
    end

    test "returns nil when nothing was recorded" do
      assert CompensationSweepWorker.reason_from(%Oban.Job{errors: []}) == nil
    end
  end

  defp pending_reply do
    email = MessagingFixtures.inbound_email_fixture()
    MessagingFixtures.email_reply_fixture(%{inbound_email_id: email.id})
  end

  defp reply_status(reply) do
    {:ok, reloaded} = Messaging.get_email_reply_by_id(reply.id)
    reloaded.status
  end

  # Written straight to the table: Oban's own insert path cannot leave a row in a
  # terminal state under `testing: :inline`.
  defp discarded_job(worker, args, opts \\ []) do
    now = DateTime.utc_now()

    Repo.insert!(%Oban.Job{
      worker: worker,
      args: args,
      queue: "email",
      state: Keyword.get(opts, :state, "discarded"),
      attempt: 3,
      max_attempts: 3,
      discarded_at: now,
      attempted_at: now,
      inserted_at: now,
      scheduled_at: now,
      errors: Keyword.get(opts, :errors, [%{"attempt" => 3, "at" => DateTime.to_iso8601(now), "error" => "boom"}])
    })
  end
end
