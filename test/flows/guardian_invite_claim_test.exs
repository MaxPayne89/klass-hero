defmodule KlassHeroWeb.Flows.GuardianInviteClaimTest do
  @moduledoc """
  Flow test for the guardian invite claim: `/invites/:token` -> magic-link login ->
  an authenticated dashboard.

  This is the chain a LiveView test structurally cannot walk — it starts in a
  controller, crosses two redirects and a session write. `invite_claim_controller_test.exs`
  stops at `redirected_to/1`; nothing followed through to a logged-in page.

  The third test drives the saga under the real outbox, so `invite_claimed` reaches
  `Family.ProcessInviteClaim` and the child and enrollment it creates show up on the
  dashboard the guardian actually lands on.
  """

  use KlassHeroWeb.FlowCase, async: false

  alias KlassHero.Accounts
  alias KlassHero.Enrollment.BulkEnrollmentInvite
  alias KlassHero.Family
  alias KlassHero.Repo

  describe "claiming an invite" do
    test "a new guardian lands authenticated on their dashboard", %{conn: conn} do
      %{token: token, email: email} = sent_invite()

      claimed = get(conn, ~p"/invites/#{token}")

      assert redirected_to(claimed) =~ "/users/log-in/"

      claimed
      |> follow_magic_link()
      |> visit(~p"/dashboard")
      |> assert_path(~p"/dashboard")

      user = Accounts.get_user_by_email(email)
      assert user != nil
      assert :parent in user.intended_roles

      assert Repo.get_by!(BulkEnrollmentInvite, guardian_email: email).status == :registered
    end

    test "a guardian who already has an account is sent to the normal login", %{conn: conn} do
      %{token: token, email: email} = sent_invite()
      existing = user_fixture(%{email: email})

      conn = get(conn, ~p"/invites/#{token}")

      assert redirected_to(conn) == ~p"/users/log-in"

      # No second account was created for the same address.
      assert Accounts.get_user_by_email(email).id == existing.id
    end

    test "an invalid token is turned away without creating anything", %{conn: conn} do
      conn
      |> visit(~p"/invites/not-a-real-token")
      |> assert_path(~p"/")
      |> assert_has("[role='alert']", text: "invalid or has expired")
    end
  end

  describe "claiming an invite, with the saga delivered" do
    test "the child and enrollment from the invite reach the dashboard", %{conn: conn} do
      %{token: token, email: email, program: program} =
        sent_invite(%{child_first_name: "Emma", child_last_name: "Schmidt"})

      claimed = with_real_outbox(fn -> get(conn, ~p"/invites/#{token}") end)

      user = Accounts.get_user_by_email(email)

      assert Repo.get_by!(BulkEnrollmentInvite, guardian_email: email).status == :enrolled
      assert {:ok, parent} = Family.get_parent_by_identity(user.id)
      assert Enum.any?(Family.get_children(parent.id), &(&1.first_name == "Emma"))

      claimed
      |> follow_magic_link()
      |> visit(~p"/dashboard")
      |> assert_has("#family-programs-list", text: program.title, timeout: 1000)
    end
  end
end
