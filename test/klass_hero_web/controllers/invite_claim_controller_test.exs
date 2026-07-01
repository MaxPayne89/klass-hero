defmodule KlassHeroWeb.InviteClaimControllerTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.Factory

  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Repo

  defp create_invite_with_token(_context) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    token = "controller-test-#{System.unique_integer([:positive])}"
    email = "controller-test-#{System.unique_integer([:positive])}@example.com"

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

    invite = Repo.one!(BulkEnrollmentInvite)

    invite
    |> Ecto.Changeset.change(%{invite_token: token, status: :invite_sent})
    |> Repo.update!()

    %{invite: Repo.one!(BulkEnrollmentInvite), token: token, email: email}
  end

  describe "GET /invites/:token" do
    setup :create_invite_with_token

    test "redirects new user to magic link login", %{conn: conn, token: token} do
      conn = get(conn, ~p"/invites/#{token}")

      assert redirected_to(conn) =~ "/users/log-in/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "account has been created"
    end

    test "redirects existing user to login", %{conn: conn, token: token, email: email} do
      # Create user with same email so claim_invite finds an existing account
      _user = user_fixture(%{email: email})

      conn = get(conn, ~p"/invites/#{token}")

      assert redirected_to(conn) == "/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "already have an account"
    end

    test "redirects to home for invalid token", %{conn: conn} do
      conn = get(conn, ~p"/invites/bad-token")

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid"
    end

    test "redirects to login for already claimed invite", %{
      conn: conn,
      token: token,
      invite: invite
    } do
      invite |> Ecto.Changeset.change(%{status: :registered}) |> Repo.update!()

      conn = get(conn, ~p"/invites/#{token}")

      assert redirected_to(conn) == "/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "already been used"
    end
  end
end
