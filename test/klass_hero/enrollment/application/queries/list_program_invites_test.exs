defmodule KlassHero.Enrollment.Application.Queries.ListProgramInvitesTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Repositories.BulkEnrollmentInviteRepository
  alias KlassHero.Enrollment.Application.Queries.ListProgramInvites

  describe "execute/1" do
    test "returns invites for a program" do
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

      {:ok, invites} = ListProgramInvites.execute(program.id)

      assert length(invites) == 1
      assert hd(invites).child_first_name == "Jane"
    end

    test "returns empty list for program with no invites" do
      {:ok, invites} = ListProgramInvites.execute(Ecto.UUID.generate())
      assert invites == []
    end
  end
end
