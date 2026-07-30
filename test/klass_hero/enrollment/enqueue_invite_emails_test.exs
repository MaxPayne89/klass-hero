defmodule KlassHero.Enrollment.EnqueueInviteEmailsTest do
  use KlassHero.DataCase, async: true
  use Oban.Testing, repo: KlassHero.Repo

  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driving.Workers.SendInviteEmailWorker
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Enrollment.EnqueueInviteEmails
  alias KlassHero.Repo

  # `testing: :inline` executes a job at insert, leaving no row to assert on.
  defp manual(fun), do: Oban.Testing.with_testing_mode(:manual, fun)

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

  describe "execute/2" do
    setup :create_pending_invites

    test "enqueues nothing when no pending invites exist", %{
      provider: provider,
      program: program
    } do
      Repo.update_all(BulkEnrollmentInvite, set: [status: :failed, error_details: "test"])

      manual(fn ->
        assert :ok = EnqueueInviteEmails.execute([program.id], provider.id)
        refute_enqueued(worker: SendInviteEmailWorker)
      end)
    end

    test "assigns a unique token to every pending invite and enqueues its email", %{
      provider: provider,
      program: program
    } do
      manual(fn ->
        assert :ok = EnqueueInviteEmails.execute([program.id], provider.id)

        invites = Repo.all(BulkEnrollmentInvite)
        tokens = Enum.map(invites, & &1.invite_token)

        assert Enum.all?(tokens, &is_binary/1)
        assert length(Enum.uniq(tokens)) == 2

        for invite <- invites do
          assert_enqueued(
            worker: SendInviteEmailWorker,
            args: %{invite_id: invite.id, program_name: "Dance Class"}
          )
        end
      end)
    end

    test "only the named invite gets a job on a resend", %{provider: provider, program: program} do
      [first, second] = Repo.all(BulkEnrollmentInvite)

      manual(fn ->
        assert :ok = EnqueueInviteEmails.execute_for_invite(program.id, provider.id, first.id)

        assert_enqueued(worker: SendInviteEmailWorker, args: %{invite_id: first.id})
        refute_enqueued(worker: SendInviteEmailWorker, args: %{invite_id: second.id})
      end)
    end

    test "falls back to 'Program' when program not in catalog", %{provider: provider} do
      # Trigger: invite has a program_id belonging to a different provider
      # Why: ACL only returns programs for the queried provider
      # Outcome: use case falls back to generic "Program" label
      other_provider = insert(:provider_profile_schema)
      orphan_program = insert(:program_schema, provider_id: other_provider.id, title: "Other")

      {:ok, _} =
        KlassHero.Enrollment.create_invite(%{
          program_id: orphan_program.id,
          provider_id: provider.id,
          child_first_name: "Orphan",
          child_last_name: "Child",
          child_date_of_birth: ~D[2016-01-01],
          guardian_email: "orphan@example.com"
        })

      # Move existing invites to non-pending so only the orphan gets picked up
      from(s in BulkEnrollmentInvite,
        where: s.program_id != ^orphan_program.id
      )
      |> Repo.update_all(set: [status: :failed, error_details: "test"])

      manual(fn ->
        assert :ok = EnqueueInviteEmails.execute([orphan_program.id], provider.id)
        assert_enqueued(worker: SendInviteEmailWorker, args: %{program_name: "Program"})
      end)
    end

    test "a second call enqueues nothing — every invite already has a token", %{
      provider: provider,
      program: program
    } do
      assert :ok = EnqueueInviteEmails.execute([program.id], provider.id)

      manual(fn ->
        assert :ok = EnqueueInviteEmails.execute([program.id], provider.id)
        refute_enqueued(worker: SendInviteEmailWorker)
      end)
    end
  end
end
