defmodule KlassHero.Enrollment.InviteClaimSagaTest do
  @moduledoc """
  Integration test for the full invite claim saga: token claim -> user creation ->
  `invite_claimed` -> family creation -> `invite_family_ready` -> enrollment.

  Every hop travels through the outbox (ADR-0014). Manual testing mode plus explicit
  drains is what makes this resemble production: under the suite's `testing: :inline`,
  staging executes the delivery job at insert — inside the producer's transaction — so
  the whole chain collapses into one synchronous cascade in which no job is ever
  retried, a sequencing production never has.
  """

  use KlassHero.DataCase, async: false

  import KlassHero.Factory

  alias KlassHero.Accounts
  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Enrollment.ClaimResult
  alias KlassHero.Family
  alias KlassHero.Shared.Adapters.Driven.Events.ObanOutbox

  defp create_claimable_invite(_context) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)

    token = "saga-test-#{System.unique_integer([:positive])}"
    email = "saga-test-#{System.unique_integer([:positive])}@example.com"

    {:ok, _} =
      Enrollment.create_invite(%{
        program_id: program.id,
        provider_id: provider.id,
        child_first_name: "Emma",
        child_last_name: "Schmidt",
        child_date_of_birth: ~D[2016-03-15],
        guardian_email: email,
        guardian_first_name: "Anna",
        guardian_last_name: "Schmidt"
      })

    invite =
      BulkEnrollmentInvite
      |> Repo.get_by!(guardian_email: email)
      |> Ecto.Changeset.change(%{invite_token: token, status: :invite_sent})
      |> Repo.update!()

    %{invite: invite, token: token, program: program, provider: provider, email: email}
  end

  setup context do
    invite_data = create_claimable_invite(context)

    # The suite records staged events instead of enqueueing them; this test needs the real
    # delivery job, because the hops it asserts on are the ones that job invokes.
    original_outbox = Application.get_env(:klass_hero, :outbox)
    Application.put_env(:klass_hero, :outbox, module: ObanOutbox)
    on_exit(fn -> Application.put_env(:klass_hero, :outbox, original_outbox) end)

    invite_data
  end

  # Deliver the staged events, run the family hop they enqueue, then deliver whatever that
  # hop staged in turn. `with_scheduled` drives a failing job through its retries instead
  # of stopping at the first backoff.
  defp run_saga do
    Oban.drain_queue(queue: :events, with_recursion: true)
    Oban.drain_queue(queue: :family, with_recursion: true, with_scheduled: true)
    Oban.drain_queue(queue: :events, with_recursion: true)
  end

  describe "full invite claim saga" do
    test "claim_invite drives user -> registered -> family -> enrolled", ctx do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %ClaimResult{user_type: :new_user, user: user}} = Enrollment.claim_invite(ctx.token)

        # Marking the invite registered and staging the claim are one transaction, so this
        # holds before anything has been delivered.
        registered = Repo.get!(BulkEnrollmentInvite, ctx.invite.id)
        assert registered.status == :registered
        assert %DateTime{} = registered.registered_at

        run_saga()

        final = Repo.get!(BulkEnrollmentInvite, ctx.invite.id)
        assert final.status == :enrolled
        assert %DateTime{} = final.enrolled_at
        assert {:ok, _enrollment} = Enrollment.get_enrollment(final.enrollment_id)

        assert {:ok, parent} = Family.get_parent_by_identity(user.id)
        assert Enum.any?(Family.get_children(parent.id), &(&1.first_name == "Emma"))
      end)
    end

    # #1221, end to end. The guardian has already been told their account exists by the
    # time this hop runs, so a failure here left them with an account, no child and no
    # enrollment, and the invite stuck in :registered where no :failed filter could find it.
    test "a claim the family hop cannot process ends failed, not stuck", ctx do
      # Written past the invite changeset, which requires a first name. Both layers reject
      # this, so reaching the state takes a deliberate write — `child_date_of_birth` is
      # NOT NULL in the database and cannot be emptied at all. What is being exercised is
      # the failure path, not a claim that this row is easy to produce. It fails the same
      # way on every attempt, which is the part that matters.
      ctx.invite
      |> Ecto.Changeset.change(%{child_first_name: ""})
      |> Repo.update!()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %ClaimResult{user: user}} = Enrollment.claim_invite(ctx.token)

        run_saga()

        final = Repo.get!(BulkEnrollmentInvite, ctx.invite.id)
        assert final.status == :failed
        assert final.failure_code == :invalid_details
        assert Enum.any?(final.failure_context["fields"], &(&1["field"] == "first_name"))

        # The account is real and stays; only the enrollment never happened.
        assert Accounts.get_user_by_email(ctx.email).id == user.id

        {:ok, parent} = Family.get_parent_by_identity(user.id)
        assert Family.get_children(parent.id) == []
      end)
    end
  end
end
