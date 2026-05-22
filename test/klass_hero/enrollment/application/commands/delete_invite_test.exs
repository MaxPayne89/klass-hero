defmodule KlassHero.Enrollment.Application.Commands.DeleteInviteTest do
  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.BulkEnrollmentInviteRepository
  alias KlassHero.Enrollment.Application.Commands.DeleteInvite

  setup do
    setup_test_events()
    :ok
  end

  describe "execute/2" do
    test "deletes an invite and publishes :invite_deleted" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(%{
          program_id: program.id,
          provider_id: provider.id,
          child_first_name: "Jane",
          child_last_name: "Smith",
          child_date_of_birth: ~D[2015-06-15],
          guardian_email: "jane@test.com"
        })

      [invite] = BulkEnrollmentInviteRepository.list_by_program(program.id)

      assert :ok = DeleteInvite.execute(invite.id, provider.id)
      assert BulkEnrollmentInviteRepository.list_by_program(program.id) == []

      assert_event_published(:invite_deleted, %{
        invite_id: invite.id,
        program_id: program.id,
        provider_id: provider.id
      })
    end

    test "returns error for non-existent invite and publishes nothing" do
      assert {:error, :not_found} =
               DeleteInvite.execute(Ecto.UUID.generate(), Ecto.UUID.generate())

      assert_no_events_published()
    end

    test "returns error when provider does not own the invite and publishes nothing" do
      provider = insert(:provider_profile_schema)
      other_provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      {:ok, _} =
        BulkEnrollmentInviteRepository.create_one(%{
          program_id: program.id,
          provider_id: provider.id,
          child_first_name: "Jane",
          child_last_name: "Smith",
          child_date_of_birth: ~D[2015-06-15],
          guardian_email: "jane@test.com"
        })

      [invite] = BulkEnrollmentInviteRepository.list_by_program(program.id)

      assert {:error, :not_found} = DeleteInvite.execute(invite.id, other_provider.id)
      assert BulkEnrollmentInviteRepository.list_by_program(program.id) != []

      assert_no_events_published()
    end
  end
end
