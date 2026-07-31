defmodule KlassHero.Enrollment.ClaimInviteTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.Factory

  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Enrollment.ClaimInvite
  alias KlassHero.Enrollment.ClaimResult
  alias KlassHero.Repo

  defp create_invite_with_token(_context), do: create_invite(%{})

  defp create_invite(overrides) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    unique = System.unique_integer([:positive])
    token = "claim-test-#{unique}"
    email = "claim-test-#{unique}@example.com"

    attrs =
      Map.merge(
        %{
          program_id: program.id,
          provider_id: provider.id,
          child_first_name: "Emma",
          child_last_name: "Schmidt",
          child_date_of_birth: ~D[2016-03-15],
          guardian_email: email,
          guardian_first_name: "Anna",
          guardian_last_name: "Schmidt"
        },
        overrides
      )

    {:ok, _} = KlassHero.Enrollment.create_invite(attrs)

    invite =
      BulkEnrollmentInvite
      |> Repo.get_by!(guardian_email: attrs.guardian_email)
      |> Ecto.Changeset.change(%{invite_token: token, status: :invite_sent})
      |> Repo.update!()

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

  # Invite fields are validated far more loosely than `Accounts.User`: guardian names are
  # `max: 100` with no minimum, and `guardian_email` is `max: 160` against `User.name`'s
  # `max: 100`. So ordinary imported data can describe a guardian no valid user can be
  # built from. Each of these raised `CaseClauseError` in the controller before #1215.
  describe "execute/1 when the invite cannot produce a valid user name" do
    test "a nameless guardian with an over-long email claims under a placeholder" do
      %{token: token} =
        create_invite(%{
          guardian_first_name: nil,
          guardian_last_name: nil,
          guardian_email: String.duplicate("a", 140) <> "@example.com"
        })

      assert {:ok, %ClaimResult{user_type: :new_user, user: user}} = ClaimInvite.execute(token)

      assert user.name == "Guardian"
    end

    test "two max-length guardian names are clamped rather than rejected" do
      %{token: token} =
        create_invite(%{
          guardian_first_name: String.duplicate("a", 100),
          guardian_last_name: String.duplicate("b", 100)
        })

      assert {:ok, %ClaimResult{user_type: :new_user, user: user}} = ClaimInvite.execute(token)

      assert String.length(user.name) == 100
    end

    test "a single-initial guardian name reports registration_failed" do
      %{token: token, invite: invite} =
        create_invite(%{guardian_first_name: "A", guardian_last_name: nil})

      assert {:error, :registration_failed} = ClaimInvite.execute(token)

      # No half-created account left behind.
      assert KlassHero.Accounts.get_user_by_email(invite.guardian_email) == nil
    end
  end
end
