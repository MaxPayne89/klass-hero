defmodule KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.EnqueueInviteEmailsTest do
  use KlassHero.DataCase, async: true
  use Oban.Testing, repo: KlassHero.Repo

  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.EnqueueInviteEmails
  alias KlassHero.Enrollment.Adapters.Driving.Workers.SendInviteEmailWorker
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Enrollment.Domain.Events.EnrollmentEvents
  alias KlassHero.Repo

  defp create_pending_invites(_context) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id, title: "Dance Class")

    rows = [
      %{
        program_id: program.id,
        provider_id: provider.id,
        child_first_name: "Emma",
        child_last_name: "Schmidt",
        child_date_of_birth: ~D[2016-03-15],
        guardian_email: "parent@example.com",
        guardian_first_name: "Hans"
      },
      %{
        program_id: program.id,
        provider_id: provider.id,
        child_first_name: "Liam",
        child_last_name: "Mueller",
        child_date_of_birth: ~D[2017-01-10],
        guardian_email: "other@example.com",
        guardian_first_name: "Maria"
      }
    ]

    Enum.each(rows, fn attrs ->
      {:ok, _} = KlassHero.Enrollment.create_invite(attrs)
    end)

    %{provider: provider, program: program}
  end

  describe "handle/1" do
    setup :create_pending_invites

    test "enqueues Oban jobs for each pending invite", %{
      provider: provider,
      program: program
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        event = EnrollmentEvents.bulk_invites_imported(provider.id, [program.id], 2)
        assert :ok = EnqueueInviteEmails.handle(event)

        invites = Repo.all(BulkEnrollmentInvite)

        Enum.each(invites, fn inv ->
          assert_enqueued(
            worker: SendInviteEmailWorker,
            args: %{invite_id: inv.id, program_name: "Dance Class"}
          )
        end)
      end)
    end

    test "assigns tokens and enqueues jobs", %{provider: provider, program: program} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        event = EnrollmentEvents.bulk_invites_imported(provider.id, [program.id], 2)
        assert :ok = EnqueueInviteEmails.handle(event)

        invites = Repo.all(BulkEnrollmentInvite)
        assert Enum.all?(invites, fn inv -> inv.invite_token != nil end)
        assert length(Enum.uniq_by(invites, & &1.invite_token)) == 2
      end)
    end

    test "does nothing when no pending invites exist", %{
      provider: provider,
      program: program
    } do
      Repo.update_all(BulkEnrollmentInvite, set: [status: :failed, error_details: "test"])

      Oban.Testing.with_testing_mode(:manual, fn ->
        event = EnrollmentEvents.bulk_invites_imported(provider.id, [program.id], 0)
        assert :ok = EnqueueInviteEmails.handle(event)

        refute_enqueued(worker: SendInviteEmailWorker)
      end)
    end

    test "skips invites that already have tokens", %{provider: provider, program: program} do
      invite = Repo.all(BulkEnrollmentInvite) |> hd()
      invite |> Ecto.Changeset.change(%{invite_token: "pre-existing"}) |> Repo.update!()

      Oban.Testing.with_testing_mode(:manual, fn ->
        event = EnrollmentEvents.bulk_invites_imported(provider.id, [program.id], 2)
        assert :ok = EnqueueInviteEmails.handle(event)

        # Trigger: one invite already had a token
        # Why: list_pending_without_token filters out already-tokenized invites
        # Outcome: only the untokenized invite gets a job
        all_enqueued = all_enqueued(worker: SendInviteEmailWorker)
        assert length(all_enqueued) == 1
      end)
    end
  end

  describe "handle/1 :invite_resend_requested" do
    setup :create_pending_invites

    test "enqueues Oban job only for the resent invite", %{
      provider: provider,
      program: program
    } do
      invites = Repo.all(BulkEnrollmentInvite)
      target = hd(invites)

      Oban.Testing.with_testing_mode(:manual, fn ->
        event =
          EnrollmentEvents.invite_resend_requested(provider.id, target.id, program.id)

        assert :ok = EnqueueInviteEmails.handle(event)

        assert_enqueued(
          worker: SendInviteEmailWorker,
          args: %{invite_id: target.id, program_name: "Dance Class"}
        )

        # Other pending invites in the same program should NOT get an email
        other = Enum.find(invites, fn inv -> inv.id != target.id end)
        refute_enqueued(worker: SendInviteEmailWorker, args: %{invite_id: other.id})
      end)
    end

    test "generates a fresh token for the resent invite", %{
      provider: provider,
      program: program
    } do
      target = Repo.all(BulkEnrollmentInvite) |> hd()

      Oban.Testing.with_testing_mode(:manual, fn ->
        event =
          EnrollmentEvents.invite_resend_requested(provider.id, target.id, program.id)

        assert :ok = EnqueueInviteEmails.handle(event)

        updated = Repo.get!(BulkEnrollmentInvite, target.id)
        assert updated.invite_token != nil
      end)
    end

    test "returns :ok when no pending invites match", %{
      provider: provider,
      program: program
    } do
      # Mark each invite with a unique token so UseCase returns empty pairs
      Repo.all(BulkEnrollmentInvite)
      |> Enum.each(fn inv ->
        inv
        |> Ecto.Changeset.change(%{invite_token: "token-#{inv.id}"})
        |> Repo.update!()
      end)

      target_id = Repo.all(BulkEnrollmentInvite) |> hd() |> Map.get(:id)

      Oban.Testing.with_testing_mode(:manual, fn ->
        event =
          EnrollmentEvents.invite_resend_requested(provider.id, target_id, program.id)

        assert :ok = EnqueueInviteEmails.handle(event)
        refute_enqueued(worker: SendInviteEmailWorker)
      end)
    end

    test "does not enqueue for other pending invites in the same program", %{
      provider: provider,
      program: program
    } do
      invites = Repo.all(BulkEnrollmentInvite)
      target = hd(invites)
      other = List.last(invites)

      Oban.Testing.with_testing_mode(:manual, fn ->
        event =
          EnrollmentEvents.invite_resend_requested(provider.id, target.id, program.id)

        assert :ok = EnqueueInviteEmails.handle(event)

        all_jobs = all_enqueued(worker: SendInviteEmailWorker)
        assert length(all_jobs) == 1

        enqueued_ids = Enum.map(all_jobs, fn %{args: %{"invite_id" => id}} -> id end)
        assert target.id in enqueued_ids
        refute other.id in enqueued_ids
      end)
    end
  end
end
