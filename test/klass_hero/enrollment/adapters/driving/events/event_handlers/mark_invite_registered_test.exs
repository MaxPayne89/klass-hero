defmodule KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.MarkInviteRegisteredTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.BulkEnrollmentInviteRepository
  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.BulkEnrollmentInviteSchema
  alias KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.MarkInviteRegistered
  alias KlassHero.Enrollment.Domain.Events.EnrollmentEvents
  alias KlassHero.Repo

  defp create_invite_sent(_context) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)

    {:ok, _} =
      BulkEnrollmentInviteRepository.create_one(%{
        program_id: program.id,
        provider_id: provider.id,
        child_first_name: "Emma",
        child_last_name: "Schmidt",
        child_date_of_birth: ~D[2016-03-15],
        guardian_email: "parent@example.com"
      })

    invite = Repo.one!(BulkEnrollmentInviteSchema)

    # Trigger: invite starts as "pending", must be "invite_sent" for this test
    # Why: MarkInviteRegistered expects the invite_sent -> registered transition
    # Outcome: bypass state machine to set up the precondition directly
    invite
    |> Ecto.Changeset.change(%{invite_token: "test-token", status: :invite_sent})
    |> Repo.update!()

    %{invite: Repo.one!(BulkEnrollmentInviteSchema), provider: provider, program: program}
  end

  describe "handle/1" do
    setup :create_invite_sent

    test "transitions invite from invite_sent to registered", %{invite: invite} do
      event =
        EnrollmentEvents.invite_claimed(invite.id, %{
          invite_id: invite.id,
          user_id: Ecto.UUID.generate()
        })

      assert :ok = MarkInviteRegistered.handle(event)

      updated = Repo.get!(BulkEnrollmentInviteSchema, invite.id)
      assert updated.status == :registered
      assert updated.registered_at != nil
    end

    test "is idempotent when already registered", %{invite: invite} do
      invite
      |> Ecto.Changeset.change(%{
        status: :registered,
        registered_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()

      event =
        EnrollmentEvents.invite_claimed(invite.id, %{
          invite_id: invite.id,
          user_id: Ecto.UUID.generate()
        })

      assert :ok = MarkInviteRegistered.handle(event)

      # Status remains registered (not changed)
      updated = Repo.get!(BulkEnrollmentInviteSchema, invite.id)
      assert updated.status == :registered
    end

    test "is idempotent when already enrolled", %{invite: invite} do
      invite
      |> Ecto.Changeset.change(%{
        status: :registered,
        registered_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()

      # Move to enrolled
      invite_refreshed = Repo.get!(BulkEnrollmentInviteSchema, invite.id)

      invite_refreshed
      |> Ecto.Changeset.change(%{
        status: :enrolled,
        enrolled_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()

      event =
        EnrollmentEvents.invite_claimed(invite.id, %{
          invite_id: invite.id,
          user_id: Ecto.UUID.generate()
        })

      assert :ok = MarkInviteRegistered.handle(event)

      # Status remains enrolled (not regressed)
      updated = Repo.get!(BulkEnrollmentInviteSchema, invite.id)
      assert updated.status == :enrolled
    end

    test "returns :ok when invite not found" do
      nonexistent_id = Ecto.UUID.generate()

      event =
        EnrollmentEvents.invite_claimed(nonexistent_id, %{
          invite_id: nonexistent_id,
          user_id: Ecto.UUID.generate()
        })

      assert :ok = MarkInviteRegistered.handle(event)
    end
  end
end
