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

    test "fails the invite with a cause a provider can act on", %{invite: invite} do
      assert {:ok, failed} = Enrollment.fail_invite(invite.id, :program_full)

      assert failed.status == :failed
      assert failed.failure_code == :program_full
    end

    # The sentence column is superseded, and a writer that still filled it would put the
    # provider back in front of copy frozen in this process's locale (#1340).
    test "writes no sentence into the legacy column", %{invite: invite} do
      assert {:ok, failed} = Enrollment.fail_invite(invite.id, :program_full)

      assert failed.error_details == nil
    end

    test "reads the missing token off the row, not off the reason", %{invite: invite} do
      invite |> Ecto.Changeset.change(%{invite_token: nil}) |> Repo.update!()

      # nil is what the compensation sweep hands back for a Lifeline discard — the path
      # on which no reason term survives at all.
      assert {:ok, failed} = Enrollment.fail_invite(invite.id, nil)
      assert failed.failure_code == :no_token
    end

    # `@valid_transitions` (failed: [:pending]) is what stops a second compensation
    # overwriting the first one's reason. It is no longer the *only* guard — since #1339
    # the marker stops a job being compensated twice at all — but it still catches the
    # cases the marker cannot, such as two different jobs failing the same invite.
    test "refuses to re-fail an invite that is already failed", %{invite: invite} do
      assert {:ok, _} = Enrollment.fail_invite(invite.id, :program_full)

      assert {:error, :already_terminal} = Enrollment.fail_invite(invite.id, nil)

      assert Repo.get!(BulkEnrollmentInvite, invite.id).failure_code == :program_full,
             "the second call overwrote the first call's reason"
    end

    test "reports a missing invite rather than raising" do
      assert {:error, :not_found} = Enrollment.fail_invite(Ecto.UUID.generate(), :program_full)
    end
  end

  # A compensation speaks for a job that is already dead, so it must not describe an
  # invite the provider has since resent — `failed: [:pending]` reopens the transition
  # the state machine was otherwise relying on to reject it (#1339).
  describe "fail_invite/3" do
    setup :create_invite

    @enqueued_at ~U[2026-08-14 12:00:00.000000Z]

    # Offsets are relative to when the job was enqueued. Equality is the resend's *own*
    # job and must still compensate: both timestamps come from the one transaction that
    # reset the invite and enqueued its email.
    for {label, offset_seconds, outcome} <- [
          {"was never resent", nil, :fails},
          {"was resent before the job was enqueued", -60, :fails},
          {"was resent as the job was enqueued", 0, :fails},
          {"was resent after the job was enqueued", 60, :superseded}
        ] do
      test "an invite that #{label} #{if outcome == :fails, do: "fails", else: "is superseded"}",
           %{invite: invite} do
        resent_at =
          case unquote(offset_seconds) do
            nil -> nil
            seconds -> DateTime.add(@enqueued_at, seconds, :second)
          end

        invite |> Ecto.Changeset.change(%{resent_at: resent_at}) |> Repo.update!()

        result = Enrollment.fail_invite(invite.id, :program_full, @enqueued_at)

        case unquote(outcome) do
          :fails ->
            assert {:ok, failed} = result, "expected an invite that #{unquote(label)} to fail"
            assert failed.status == :failed

          :superseded ->
            assert {:error, :superseded} = result,
                   "expected an invite that #{unquote(label)} to be left alone"

            assert Repo.get!(BulkEnrollmentInvite, invite.id).status == :pending
        end
      end
    end

    test "leaves the reason of a superseded invite untouched", %{invite: invite} do
      invite
      |> Ecto.Changeset.change(%{resent_at: DateTime.add(@enqueued_at, 60, :second)})
      |> Repo.update!()

      assert {:error, :superseded} = Enrollment.fail_invite(invite.id, :program_full, @enqueued_at)

      assert Repo.get!(BulkEnrollmentInvite, invite.id).failure_code == nil
    end

    test "reports a missing invite rather than raising" do
      assert {:error, :not_found} =
               Enrollment.fail_invite(Ecto.UUID.generate(), :program_full, @enqueued_at)
    end
  end

  describe "reset_invite_for_resend/1" do
    setup :create_invite

    test "clears the cause so the reopened invite shows no reason", %{invite: invite} do
      {:ok, failed} = Enrollment.fail_invite(invite.id, {:invalid_date, "not-a-date"})
      assert failed.failure_code == :invalid_date

      assert {:ok, reset} = Enrollment.reset_invite_for_resend(failed)

      assert reset.status == :pending
      assert reset.failure_code == nil
      assert reset.failure_context == nil
    end

    # An invite that failed before #1340 carries its reason in the old column, and a
    # resend has to clear that one too or the reopened invite keeps the old sentence.
    test "clears a legacy sentence as well", %{invite: invite} do
      failed =
        invite
        |> Ecto.Changeset.change(%{status: :failed, error_details: "The program is full."})
        |> Repo.update!()

      assert {:ok, reset} = Enrollment.reset_invite_for_resend(failed)

      assert reset.error_details == nil
    end
  end
end
