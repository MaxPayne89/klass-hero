defmodule KlassHero.Enrollment.ClaimInviteTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.Factory

  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Enrollment.ClaimInvite
  alias KlassHero.Enrollment.ClaimResult
  alias KlassHero.Repo

  defp create_invite_with_token(_context) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    unique = System.unique_integer([:positive])
    token = "claim-test-#{unique}"
    email = "claim-test-#{unique}@example.com"

    {:ok, _} =
      KlassHero.Enrollment.create_invite(%{
        program_id: program.id,
        provider_id: provider.id,
        child_first_name: "Emma",
        child_last_name: "Schmidt",
        child_date_of_birth: ~D[2016-03-15],
        guardian_email: email,
        guardian_first_name: "Anna",
        guardian_last_name: "Schmidt"
      })

    # Fetch the created invite and manually assign the token + status
    invite =
      BulkEnrollmentInvite
      |> Repo.one!()
      |> Ecto.Changeset.change(%{invite_token: token, status: :invite_sent})
      |> Repo.update!()

    # Re-fetch to get clean state
    invite = Repo.get!(BulkEnrollmentInvite, invite.id)

    %{invite: invite, token: token, program: program, provider: provider}
  end

  describe "execute/1" do
    setup :create_invite_with_token

    test "returns not_found for invalid token" do
      assert {:error, :not_found} = ClaimInvite.execute("bad-token")
    end

    test "returns already_claimed when status is not invite_sent", %{invite: invite, token: token} do
      invite |> Ecto.Changeset.change(%{status: :registered}) |> Repo.update!()

      assert {:error, :already_claimed} = ClaimInvite.execute(token)
    end

    test "creates new user for unknown email", %{token: token, invite: invite} do
      assert {:ok, %ClaimResult{user_type: :new_user, user: user, invite: returned_invite}} =
               ClaimInvite.execute(token)

      assert user.email == invite.guardian_email
      assert user.name == "Anna Schmidt"
      assert returned_invite.id == Ecto.UUID.cast!(invite.id)
    end

    test "returns existing user when email matches", %{token: token, invite: invite} do
      existing_user = user_fixture(%{email: invite.guardian_email})

      assert {:ok, %ClaimResult{user_type: :existing_user, user: user}} =
               ClaimInvite.execute(token)

      assert user.id == existing_user.id
    end
  end
end
