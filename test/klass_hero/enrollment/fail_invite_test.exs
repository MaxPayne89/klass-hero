defmodule KlassHero.Enrollment.FailInviteTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Repo

  defp create_invite(_context) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id, title: "Dance Class")

    {:ok, _} =
      Enrollment.create_invite(%{
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

  describe "fail_invite/2" do
    setup :create_invite

    test "fails the invite with a reason a provider can act on", %{invite: invite} do
      assert {:ok, failed} = Enrollment.fail_invite(invite.id, :program_full)

      assert failed.status == :failed
      assert failed.error_details =~ "full"
      refute failed.error_details =~ ":program_full"
    end

    test "reads the missing token off the row, not off the reason", %{invite: invite} do
      invite |> Ecto.Changeset.change(%{invite_token: nil}) |> Repo.update!()

      # nil is what the compensation sweep hands back for a Lifeline discard — the path
      # on which no reason term survives at all.
      assert {:ok, failed} = Enrollment.fail_invite(invite.id, nil)
      assert failed.error_details =~ "no token"
    end

    # This rejection is what keeps compensation idempotent: a worker compensates inline
    # on its final attempt, and the sweep then re-examines the same discarded job. Both
    # land here, and `@valid_transitions` (failed: [:pending]) is the only thing that
    # stops the second one overwriting the first one's reason.
    test "refuses to re-fail an invite that is already failed", %{invite: invite} do
      assert {:ok, _} = Enrollment.fail_invite(invite.id, :program_full)

      assert {:error, :already_terminal} = Enrollment.fail_invite(invite.id, nil)

      assert Repo.get!(BulkEnrollmentInvite, invite.id).error_details =~ "full",
             "the second call overwrote the first call's reason"
    end

    test "reports a missing invite rather than raising" do
      assert {:error, :not_found} = Enrollment.fail_invite(Ecto.UUID.generate(), :program_full)
    end
  end
end
