defmodule KlassHero.Enrollment.Adapters.Driving.Workers.SendInviteEmailWorkerTest do
  use KlassHero.DataCase, async: true

  import ExUnit.CaptureLog
  import KlassHero.Factory
  import Swoosh.TestAssertions

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.Adapters.Driving.Workers.SendInviteEmailWorker
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Workers.CompensationSweepWorker
  alias KlassHero.Test.StubMailerAdapter

  defp create_pending_invite(_context) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id, title: "Dance Class")

    {:ok, _} =
      KlassHero.Enrollment.create_invite(%{
        program_id: program.id,
        provider_id: provider.id,
        child_first_name: "Emma",
        child_last_name: "Schmidt",
        child_date_of_birth: ~D[2016-03-15],
        guardian_email: "parent@example.com",
        guardian_first_name: "Hans"
      })

    invite = Repo.one!(BulkEnrollmentInvite)
    invite = invite |> Ecto.Changeset.change(%{invite_token: "test-token-123"}) |> Repo.update!()

    %{invite: invite, program: program}
  end

  describe "perform/1" do
    setup :create_pending_invite

    test "sends email and transitions to invite_sent", %{invite: invite, program: program} do
      assert :ok =
               SendInviteEmailWorker.perform(%Oban.Job{
                 args: %{"invite_id" => invite.id, "program_name" => program.title}
               })

      updated = Repo.get!(BulkEnrollmentInvite, invite.id)
      assert updated.status == :invite_sent
      assert updated.invite_sent_at != nil
    end

    test "skips already-sent invite", %{invite: invite, program: program} do
      invite
      |> BulkEnrollmentInvite.transition_changeset(%{
        status: :invite_sent,
        invite_sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()

      assert :ok =
               SendInviteEmailWorker.perform(%Oban.Job{
                 args: %{"invite_id" => invite.id, "program_name" => program.title}
               })
    end

    test "returns :not_found for missing invite" do
      assert :ok =
               SendInviteEmailWorker.perform(%Oban.Job{
                 args: %{"invite_id" => Ecto.UUID.generate(), "program_name" => "Dance"}
               })
    end

    # A retry re-reads the same nil token, so every remaining attempt is guaranteed
    # waste — cancel instead of burning the retry budget, and fail the invite now so
    # it surfaces as Failed rather than sitting :pending with no email forever.
    test "cancels and fails an invite that has no token", %{invite: invite, program: program} do
      invite |> Ecto.Changeset.change(%{invite_token: nil}) |> Repo.update!()

      assert {:cancel, "invite has no token"} =
               SendInviteEmailWorker.perform(%Oban.Job{
                 args: %{"invite_id" => invite.id, "program_name" => program.title}
               })

      failed = Repo.get!(BulkEnrollmentInvite, invite.id)
      assert failed.status == :failed
      assert failed.error_details =~ "no token"
    end
  end

  # #1233: this worker failed the invite on the *first* delivery error, then returned
  # {:error, _} so Oban retried — and the retry hit the non-pending guard above and
  # reported :ok. One transient blip permanently failed an invite and called it a
  # success. These build %Oban.Job{} structs by hand because the behaviour under test
  # is a decision about attempt vs max_attempts, which a drained queue cannot express.
  describe "execute/1 compensation" do
    setup :create_pending_invite

    @max_attempts 3

    # `id`, `worker` and `inserted_at` are populated because a job reaching the
    # compensation gate came out of `oban_jobs`: the first two key its compensation
    # marker, and the third is the watermark a resend is measured against (#1339).
    defp job(invite, program, attempt, opts \\ []) do
      %Oban.Job{
        id: System.unique_integer([:positive]),
        worker: Oban.Worker.to_string(SendInviteEmailWorker),
        args: %{"invite_id" => invite.id, "program_name" => program.title},
        attempt: attempt,
        max_attempts: @max_attempts,
        inserted_at: Keyword.get(opts, :inserted_at, DateTime.utc_now())
      }
    end

    defp reload(invite), do: Repo.get!(BulkEnrollmentInvite, invite.id)

    # pending -> :failed is a one-way door (:failed can only return to :pending), so
    # failing while Oban would still retry destroys the send the next attempt makes.
    test "leaves the invite pending while retries remain", %{invite: invite, program: program} do
      StubMailerAdapter.fail_with({:network, :timeout})

      for attempt <- 1..(@max_attempts - 1) do
        assert {:error, _reason} = SendInviteEmailWorker.execute(job(invite, program, attempt))

        assert reload(invite).status == :pending,
               "attempt #{attempt} of #{@max_attempts} failed the invite before retries were exhausted"
      end
    end

    # The whole point of retrying: the guardian gets the invite a blip nearly cost them.
    test "delivers on the retry after a transient failure", %{invite: invite, program: program} do
      StubMailerAdapter.fail_with({:network, :timeout})
      assert {:error, _reason} = SendInviteEmailWorker.execute(job(invite, program, 1))

      StubMailerAdapter.deliver_normally()
      assert :ok = SendInviteEmailWorker.execute(job(invite, program, 2))

      delivered = reload(invite)
      assert delivered.status == :invite_sent
      assert delivered.invite_sent_at != nil
      assert_email_sent(fn email -> email.to == [{"Hans", "parent@example.com"}] end)
    end

    test "fails the invite once retries are exhausted", %{invite: invite, program: program} do
      StubMailerAdapter.fail_with({:network, :timeout})

      assert {:error, _reason} =
               SendInviteEmailWorker.execute(job(invite, program, @max_attempts))

      failed = reload(invite)
      assert failed.status == :failed
      assert failed.error_details =~ "could not be delivered"
      refute failed.error_details =~ "network", "the mailer's own term reached the provider"
    end

    # Oban reads retry/discard off the return value; compensating must not look to it
    # like the job succeeded, or the failure is invisible in the jobs table too.
    test "still returns the error after compensating", %{invite: invite, program: program} do
      StubMailerAdapter.fail_with({:network, :timeout})

      assert {:error, _reason} =
               SendInviteEmailWorker.execute(job(invite, program, @max_attempts))
    end
  end

  # #1339. A compensation speaks for a job that is already dead, and between that death
  # and the compensation running the provider can resend — `failed: [:pending]` reopens
  # the transition the state machine was otherwise relying on to reject a second failure.
  describe "compensate/2 after a resend" do
    setup :create_pending_invite

    test "leaves an invite resent after this job was enqueued alone", %{invite: invite, program: program} do
      dead = job(invite, program, @max_attempts, inserted_at: minutes_ago(30))

      {:ok, _resent} = Enrollment.reset_invite_for_resend(invite)

      assert :ignore = SendInviteEmailWorker.compensate(dead, {:network, :timeout})

      resent = reload(invite)
      assert resent.status == :pending, "a dead job re-failed an invite the provider had resent"
      assert resent.error_details == nil, "a dead job overwrote the reason a resend had cleared"
    end

    # The other side of the guard: without a resend to supersede it, the compensation is
    # still the whole point of the mechanism.
    test "still fails an invite that was never resent", %{invite: invite, program: program} do
      dead = job(invite, program, @max_attempts, inserted_at: minutes_ago(30))

      assert :ok = SendInviteEmailWorker.compensate(dead, {:network, :timeout})
      assert reload(invite).status == :failed
    end

    # The full reported sequence, through the real sweep rather than a direct call:
    # exhaust the attempts, resend, then let the sweep reach the discarded job.
    test "survives the compensation sweep after a resend", %{invite: invite, program: program} do
      StubMailerAdapter.fail_with({:network, :timeout})

      assert {:error, _reason} =
               SendInviteEmailWorker.execute(job(invite, program, @max_attempts))

      assert reload(invite).status == :failed

      {:ok, _resent} = Enrollment.resend_invite(invite.id, invite.provider_id)
      assert reload(invite).status == :pending

      discarded_send_job(invite, program)
      assert :ok = CompensationSweepWorker.perform(%Oban.Job{})

      swept = reload(invite)
      assert swept.status == :pending, "the sweep re-failed an invite the provider had resent"
      assert swept.error_details == nil
    end

    # The guard's sharpest edge. `resent_at` and a job's `inserted_at` are only
    # comparable if they come from the SAME clock, and left to itself `inserted_at` does
    # not: the column defaults to Postgres `now()`, which is (a) the database server's
    # clock, skewed from this VM's by however far the two have drifted, and (b) frozen at
    # *transaction start* — before the `resent_at` the same transaction goes on to write,
    # since `resend_invite/2` resets and enqueues together.
    #
    # Either alone makes a resend enqueue a job its own guard reads as superseded,
    # silently disabling compensation for exactly the invites this protects. So the
    # assertion is on the clock source rather than on an ordering: the window is
    # microseconds wide, and only a timestamp taken by this VM can land inside it.
    test "stamps the enqueue time from the application clock, not the database's", %{invite: invite} do
      before_resend = DateTime.utc_now()

      {:ok, _resent} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          Enrollment.resend_invite(invite.id, invite.provider_id)
        end)

      after_resend = DateTime.utc_now()
      enqueued_at = resend_job().inserted_at

      assert DateTime.compare(enqueued_at, before_resend) != :lt and
               DateTime.compare(enqueued_at, after_resend) != :gt,
             "inserted_at #{inspect(enqueued_at)} fell outside #{inspect(before_resend)}..." <>
               "#{inspect(after_resend)}, so it came from the database clock, not this one"
    end

    # The behaviour resting on it: a resend's own job is not superseded by the resend that
    # enqueued it, so its compensation still lands if that send then fails for good.
    test "compensates for the job its own resend enqueued", %{invite: invite} do
      {:ok, _resent} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          Enrollment.resend_invite(invite.id, invite.provider_id)
        end)

      assert :ok = SendInviteEmailWorker.compensate(resend_job(), {:network, :timeout}),
             "the resend's own job read as superseded by the resend that enqueued it"

      assert reload(invite).status == :failed
    end

    defp resend_job do
      Repo.one!(from(j in Oban.Job, where: j.worker == ^Oban.Worker.to_string(SendInviteEmailWorker)))
    end

    defp minutes_ago(minutes), do: DateTime.add(DateTime.utc_now(), -minutes, :minute)

    # Written straight to the table: `testing: :inline` executes a job at insert, so
    # Oban's own path cannot leave one sitting in a terminal state.
    defp discarded_send_job(invite, program) do
      now = DateTime.utc_now()

      Repo.insert!(%Oban.Job{
        worker: Oban.Worker.to_string(SendInviteEmailWorker),
        args: %{"invite_id" => invite.id, "program_name" => program.title},
        queue: "email",
        state: "discarded",
        attempt: @max_attempts,
        max_attempts: @max_attempts,
        discarded_at: now,
        attempted_at: now,
        inserted_at: minutes_ago(30),
        scheduled_at: minutes_ago(30),
        errors: [%{"attempt" => 3, "at" => DateTime.to_iso8601(now), "error" => "boom"}]
      })
    end
  end

  # #1248: the tokenless branch used to discard this transition's result and return
  # {:cancel, _} regardless. A cancelled job is out of the compensation sweep's scope
  # on purpose, so a failed write left the invite :pending forever with nothing to
  # retry it and nothing logged.
  #
  # The result is injected because no fixture can produce it: the non-pending guard in
  # execute/1 catches every invite that is not :pending before this branch, and
  # transition_changeset validates against the refetched row — so by the time the
  # branch runs, pending -> :failed is always legal.
  describe "resolve_tokenless/2" do
    setup :create_pending_invite

    test "cancels once the invite is marked failed", %{invite: invite, program: program} do
      assert {:cancel, "invite has no token"} =
               SendInviteEmailWorker.resolve_tokenless({:ok, invite}, job(invite, program, 1))

      assert reload(invite).status == :pending,
             "resolve_tokenless/2 should not write; the caller already did"
    end

    test "retries a failed write while attempts remain", %{invite: invite, program: program} do
      assert {:error, :not_found} =
               SendInviteEmailWorker.resolve_tokenless({:error, :not_found}, job(invite, program, 1))

      assert reload(invite).status == :pending,
             "compensated while retries remained, destroying the write the next attempt makes"
    end

    # The token is nilled to match the only state that reaches this branch in
    # production. It is also what makes the reason right: compensate/2 is shared with
    # the delivery path, so before #1290 a missing token was reported to the provider as
    # an email delivery problem — different advice from the resend that mints a new one.
    test "compensates a failed write, naming the missing token", %{invite: invite, program: program} do
      tokenless = invite |> Ecto.Changeset.change(%{invite_token: nil}) |> Repo.update!()

      assert {:error, :not_found} =
               SendInviteEmailWorker.resolve_tokenless(
                 {:error, :not_found},
                 job(tokenless, program, @max_attempts)
               )

      failed = reload(tokenless)
      assert failed.status == :failed
      assert failed.error_details =~ "no token"
      refute failed.error_details =~ "not_found"
    end

    # Returning the error is what retries it; the log is what makes a write that keeps
    # failing visible before the retries run out.
    test "logs the failed write at :critical", %{invite: invite, program: program} do
      log =
        capture_log(fn ->
          SendInviteEmailWorker.resolve_tokenless({:error, :not_found}, job(invite, program, 1))
        end)

      assert log =~ "[critical]"
      assert log =~ "tokenless invite"
    end
  end
end
