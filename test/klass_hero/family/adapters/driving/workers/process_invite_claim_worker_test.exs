defmodule KlassHero.Family.Adapters.Driving.Workers.ProcessInviteClaimWorkerTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.Factory

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Family
  alias KlassHero.Family.Adapters.Driving.Workers.ProcessInviteClaimWorker

  @max_attempts 3

  describe "perform/1" do
    test "processes invite claim and creates parent + child" do
      user = user_fixture()

      job =
        ProcessInviteClaimWorker.new(%{
          "invite_id" => Ecto.UUID.generate(),
          "user_id" => user.id,
          "program_id" => Ecto.UUID.generate(),
          "child_first_name" => "Emma",
          "child_last_name" => "Schmidt",
          "child_date_of_birth" => "2016-03-15",
          "school_grade" => 3,
          "school_name" => "Berlin Elementary",
          "medical_conditions" => "Asthma",
          "nut_allergy" => true
        })
        |> Oban.insert!()

      assert :ok = ProcessInviteClaimWorker.perform(job)

      {:ok, parent} = Family.get_parent_by_identity(user.id)
      children = Family.get_children(parent.id)
      assert length(children) == 1
      assert hd(children).first_name == "Emma"
    end

    test "returns error for malformed date_of_birth string" do
      user = user_fixture()

      job =
        ProcessInviteClaimWorker.new(%{
          "invite_id" => Ecto.UUID.generate(),
          "user_id" => user.id,
          "program_id" => Ecto.UUID.generate(),
          "child_first_name" => "Emma",
          "child_last_name" => "Schmidt",
          "child_date_of_birth" => "not-a-date"
        })
        |> Oban.insert!()

      assert {:error, {:invalid_date, "not-a-date"}} =
               ProcessInviteClaimWorker.perform(job)
    end

    test "handles nil date_of_birth in args" do
      user = user_fixture()

      job =
        ProcessInviteClaimWorker.new(%{
          "invite_id" => Ecto.UUID.generate(),
          "user_id" => user.id,
          "program_id" => Ecto.UUID.generate(),
          "child_first_name" => "Emma",
          "child_last_name" => "Schmidt",
          "child_date_of_birth" => nil
        })
        |> Oban.insert!()

      # Will fail at domain validation (date_of_birth required), but worker should not crash
      result = ProcessInviteClaimWorker.perform(job)
      assert {:error, _reason} = result
    end
  end

  # #1221: until this existed, a claim that failed here left the guardian with an account,
  # no child and no enrollment, and froze the invite in :registered forever — a state no
  # list filtering on :failed could show. These build %Oban.Job{} structs by hand because
  # the behaviour under test is a decision about attempt vs max_attempts, and a drained
  # queue cannot express "this is the second of three tries".
  describe "execute/1 compensation" do
    setup do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      user = user_fixture()

      {:ok, _} =
        Enrollment.create_invite(%{
          program_id: program.id,
          provider_id: provider.id,
          child_first_name: "Emma",
          child_last_name: "Schmidt",
          child_date_of_birth: ~D[2016-03-15],
          guardian_email: "parent-#{System.unique_integer([:positive])}@example.com"
        })

      # The claim already happened: ClaimInvite marked the invite registered and told the
      # guardian their account exists. Everything this worker does happens after that.
      invite =
        BulkEnrollmentInvite
        |> Repo.one!()
        |> Ecto.Changeset.change(%{invite_token: "tok-1", status: :registered})
        |> Repo.update!()

      %{invite: invite, program: program, user: user}
    end

    # A nil date of birth fails Family.Child's validate_required the same way on every
    # attempt — the deterministic failure the issue describes.
    defp failing_args(invite, program, user) do
      %{
        "invite_id" => invite.id,
        "user_id" => user.id,
        "program_id" => program.id,
        "child_first_name" => "Emma",
        "child_last_name" => "Schmidt",
        "child_date_of_birth" => nil
      }
    end

    # `id`, `worker` and `inserted_at` are populated because a job reaching the
    # compensation gate came out of `oban_jobs`: the first two key its compensation
    # marker, and the third is the watermark a resend is measured against (#1339).
    defp job(args, attempt, opts \\ []) do
      %Oban.Job{
        id: System.unique_integer([:positive]),
        worker: Oban.Worker.to_string(ProcessInviteClaimWorker),
        args: args,
        attempt: attempt,
        max_attempts: @max_attempts,
        inserted_at: Keyword.get(opts, :inserted_at, DateTime.utc_now())
      }
    end

    defp reload(invite), do: Repo.get!(BulkEnrollmentInvite, invite.id)

    # failed -> enrolled is not a legal transition, so failing the invite while Oban would
    # still retry destroys a claim the next attempt would have healed.
    test "leaves the invite registered while retries remain", ctx do
      args = failing_args(ctx.invite, ctx.program, ctx.user)

      for attempt <- 1..(@max_attempts - 1) do
        assert {:error, _reason} = ProcessInviteClaimWorker.execute(job(args, attempt))

        assert reload(ctx.invite).status == :registered,
               "attempt #{attempt} of #{@max_attempts} failed the invite before retries were exhausted"
      end
    end

    # error_details is read by a provider in the invites table, not by a developer in a
    # log, so a raw inspect/1 of the changeset would be no more actionable than the
    # silence it replaced.
    test "fails the invite on the final attempt, recording a readable reason", ctx do
      args = failing_args(ctx.invite, ctx.program, ctx.user)

      assert {:error, _reason} = ProcessInviteClaimWorker.execute(job(args, @max_attempts))

      failed = reload(ctx.invite)
      assert failed.status == :failed
      assert failed.error_details =~ "date of birth"
      assert failed.error_details =~ "can't be blank"
      refute failed.error_details =~ "Ecto.Changeset"
    end

    test "records a reason for a failure that carries no changeset", ctx do
      args =
        ctx.invite
        |> failing_args(ctx.program, ctx.user)
        |> Map.put("child_date_of_birth", "not-a-date")

      assert {:error, _reason} = ProcessInviteClaimWorker.execute(job(args, @max_attempts))

      assert reload(ctx.invite).error_details =~ "not-a-date"
    end

    # Oban reads retry/discard off the return value; compensating must not look to it
    # like the job succeeded.
    test "still returns the error after compensating", ctx do
      args = failing_args(ctx.invite, ctx.program, ctx.user)

      assert {:error, _reason} = ProcessInviteClaimWorker.execute(job(args, @max_attempts))
    end

    # Lifeline can re-run a job whose earlier attempt already committed, so the final
    # attempt can arrive at an invite that has moved on. transition_invite/2 rejects
    # enrolled -> failed, and that rejection is the correct outcome, not a crash.
    test "does not disturb an invite that already reached a terminal state", ctx do
      {:ok, enrolled} = Enrollment.transition_invite(ctx.invite, %{status: :enrolled})
      args = failing_args(ctx.invite, ctx.program, ctx.user)

      assert {:error, _reason} = ProcessInviteClaimWorker.execute(job(args, @max_attempts))

      assert reload(enrolled).status == :enrolled
    end

    test "leaves the invite alone when the claim succeeds", ctx do
      args =
        ctx.invite
        |> failing_args(ctx.program, ctx.user)
        |> Map.put("child_date_of_birth", "2016-03-15")

      assert :ok = ProcessInviteClaimWorker.execute(job(args, 1))

      # Reaching :enrolled is InviteFamilyReadyHandler's job, one hop downstream.
      assert reload(ctx.invite).status == :registered
    end
  end
end
