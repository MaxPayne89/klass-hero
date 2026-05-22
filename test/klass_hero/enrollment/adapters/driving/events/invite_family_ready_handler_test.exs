defmodule KlassHero.Enrollment.Adapters.Driving.Events.InviteFamilyReadyHandlerTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.BulkEnrollmentInviteRepository
  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.BulkEnrollmentInviteSchema
  alias KlassHero.Enrollment.Adapters.Driving.Events.InviteFamilyReadyHandler
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  defp create_registered_invite(_context) do
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

    # Trigger: invite starts as "pending", must be "registered" for this handler
    # Why: InviteFamilyReadyHandler expects registered -> enrolled transition
    # Outcome: bypass state machine to set up the precondition directly
    invite
    |> Ecto.Changeset.change(%{invite_token: "test-token", status: :registered})
    |> Repo.update!()

    invite = Repo.one!(BulkEnrollmentInviteSchema)

    # Create parent + child for enrollment (must exist in DB for FK constraints)
    parent = insert(:parent_profile_schema)
    {child, _} = insert_child_with_guardian(parent: parent)

    %{invite: invite, provider: provider, program: program, parent: parent, child: child}
  end

  describe "subscribed_events/0" do
    test "subscribes to :invite_family_ready" do
      assert [:invite_family_ready] = InviteFamilyReadyHandler.subscribed_events()
    end
  end

  describe "handle_event/1" do
    setup :create_registered_invite

    test "creates enrollment and transitions invite to enrolled", %{
      invite: invite,
      program: program,
      parent: parent,
      child: child
    } do
      event =
        IntegrationEvent.new(
          :invite_family_ready,
          :family,
          :invite,
          invite.id,
          %{
            invite_id: invite.id,
            user_id: Ecto.UUID.generate(),
            child_id: child.id,
            parent_id: parent.id,
            program_id: program.id
          }
        )

      assert :ok = InviteFamilyReadyHandler.handle_event(event)

      updated = Repo.get!(BulkEnrollmentInviteSchema, invite.id)
      assert updated.status == :enrolled
      assert updated.enrolled_at != nil
      assert updated.enrollment_id != nil
    end

    test "is idempotent when invite already enrolled", %{invite: invite} do
      # Transition to enrolled first
      invite
      |> Ecto.Changeset.change(%{
        status: :enrolled,
        enrolled_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()

      event =
        IntegrationEvent.new(
          :invite_family_ready,
          :family,
          :invite,
          invite.id,
          %{
            invite_id: invite.id,
            user_id: Ecto.UUID.generate(),
            child_id: Ecto.UUID.generate(),
            parent_id: Ecto.UUID.generate(),
            program_id: Ecto.UUID.generate()
          }
        )

      assert :ok = InviteFamilyReadyHandler.handle_event(event)
    end

    test "returns :ok for nonexistent invite" do
      event =
        IntegrationEvent.new(
          :invite_family_ready,
          :family,
          :invite,
          Ecto.UUID.generate(),
          %{
            invite_id: Ecto.UUID.generate(),
            user_id: Ecto.UUID.generate(),
            child_id: Ecto.UUID.generate(),
            parent_id: Ecto.UUID.generate(),
            program_id: Ecto.UUID.generate()
          }
        )

      assert :ok = InviteFamilyReadyHandler.handle_event(event)
    end

    test "ignores unrelated events" do
      event = IntegrationEvent.new(:something_else, :other, :thing, "id", %{})
      assert :ignore = InviteFamilyReadyHandler.handle_event(event)
    end
  end
end
