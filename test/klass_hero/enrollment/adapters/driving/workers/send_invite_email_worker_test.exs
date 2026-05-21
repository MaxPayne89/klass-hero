defmodule KlassHero.Enrollment.Adapters.Driving.Workers.SendInviteEmailWorkerTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.BulkEnrollmentInviteRepository
  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.BulkEnrollmentInviteSchema
  alias KlassHero.Enrollment.Adapters.Driving.Workers.SendInviteEmailWorker
  alias KlassHero.Repo

  defp create_pending_invite(_context) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id, title: "Dance Class")

    {:ok, _} =
      BulkEnrollmentInviteRepository.create_one(%{
        program_id: program.id,
        provider_id: provider.id,
        child_first_name: "Emma",
        child_last_name: "Schmidt",
        child_date_of_birth: ~D[2016-03-15],
        guardian_email: "parent@example.com",
        guardian_first_name: "Hans"
      })

    invite = Repo.one!(BulkEnrollmentInviteSchema)
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

      updated = Repo.get!(BulkEnrollmentInviteSchema, invite.id)
      assert updated.status == :invite_sent
      assert updated.invite_sent_at != nil
    end

    test "skips already-sent invite", %{invite: invite, program: program} do
      invite
      |> BulkEnrollmentInviteSchema.transition_changeset(%{
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

    test "returns error when invite has no token", %{invite: invite, program: program} do
      invite |> Ecto.Changeset.change(%{invite_token: nil}) |> Repo.update!()

      assert {:error, "invite has no token"} =
               SendInviteEmailWorker.perform(%Oban.Job{
                 args: %{"invite_id" => invite.id, "program_name" => program.title}
               })
    end
  end
end
