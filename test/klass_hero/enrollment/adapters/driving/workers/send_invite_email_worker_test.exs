defmodule KlassHero.Enrollment.Adapters.Driving.Workers.SendInviteEmailWorkerTest do
  use KlassHero.DataCase, async: true

  import ExUnit.CaptureLog
  import KlassHero.Factory
  import Swoosh.TestAssertions

  alias KlassHero.Enrollment.Adapters.Driving.Workers.SendInviteEmailWorker
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Repo
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

    defp job(invite, program, attempt) do
      %Oban.Job{
        args: %{"invite_id" => invite.id, "program_name" => program.title},
        attempt: attempt,
        max_attempts: @max_attempts
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
