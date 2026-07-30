defmodule KlassHero.Enrollment.DeleteInviteTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  describe "execute/2" do
    test "deletes an invite" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      {:ok, _} =
        KlassHero.Enrollment.create_invite(%{
          program_id: program.id,
          provider_id: provider.id,
          child_first_name: "Jane",
          child_last_name: "Smith",
          child_date_of_birth: ~D[2015-06-15],
          guardian_email: "jane@test.com"
        })

      {:ok, [invite]} = KlassHero.Enrollment.list_program_invites(program.id)

      assert :ok = KlassHero.Enrollment.delete_invite(invite.id, provider.id)
      assert KlassHero.Enrollment.list_program_invites(program.id) == {:ok, []}
    end

    test "returns error for non-existent invite" do
      assert {:error, :not_found} =
               KlassHero.Enrollment.delete_invite(Ecto.UUID.generate(), Ecto.UUID.generate())
    end

    test "returns error when provider does not own the invite and publishes nothing" do
      provider = insert(:provider_profile_schema)
      other_provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      {:ok, _} =
        KlassHero.Enrollment.create_invite(%{
          program_id: program.id,
          provider_id: provider.id,
          child_first_name: "Jane",
          child_last_name: "Smith",
          child_date_of_birth: ~D[2015-06-15],
          guardian_email: "jane@test.com"
        })

      {:ok, [invite]} = KlassHero.Enrollment.list_program_invites(program.id)

      assert {:error, :not_found} = KlassHero.Enrollment.delete_invite(invite.id, other_provider.id)
      assert KlassHero.Enrollment.list_program_invites(program.id) != {:ok, []}
    end
  end
end
