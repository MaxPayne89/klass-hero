defmodule KlassHeroWeb.InviteClaimControllerTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.Factory

  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Repo

  defp create_invite_with_token(_context), do: create_invite(%{})

  defp create_invite(overrides) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    token = "controller-test-#{System.unique_integer([:positive])}"
    email = "controller-test-#{System.unique_integer([:positive])}@example.com"

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

    %{invite: invite, token: token, email: attrs.guardian_email}
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

  describe "GET /invites/:token when the account cannot be created" do
    # Invite names are validated `max: 100` with no minimum, but `User.name` is
    # `min: 2` — so a CSV carrying initials produces a registration failure with
    # no user to recover to. `claim_invite/1` must report it as an atom the
    # controller handles, not raise CaseClauseError on a leaked changeset.
    test "redirects with a generic error rather than 500ing", %{conn: conn} do
      %{token: token} = create_invite(%{guardian_first_name: "A", guardian_last_name: nil})

      conn = get(conn, ~p"/invites/#{token}")

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Something went wrong"
    end
  end
end
