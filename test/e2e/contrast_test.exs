defmodule KlassHeroWeb.E2E.ContrastTest do
  @moduledoc """
  Every visible text node on a representative route clears its WCAG AA floor.

  `mix lint_palette` guards the declared tokens; this guards what actually
  paints. They disagree in both directions, which is why both exist — see
  `KlassHeroWeb.E2E.ContrastAudit`.

  Routes are chosen for their *surface*, not their features: the three shells
  (white marketing, pink parent, cream provider) are where the same muted token
  lands on different backgrounds, and that is the mistake a class-level check
  cannot see.
  """

  use KlassHeroWeb.E2ECase

  alias KlassHeroWeb.E2E.ContrastAudit

  setup %{sandbox_metadata: metadata} do
    {:ok, session: new_session(metadata)}
  end

  defp assert_no_contrast_failures(session, route) do
    failures = ContrastAudit.failures(session)

    assert failures == [],
           "#{route} has #{length(failures)} text node(s) below the WCAG AA floor:\n" <>
             ContrastAudit.format(failures)
  end

  describe "public surfaces" do
    test "the home page clears AA", %{session: session} do
      session
      |> visit("/")
      |> assert_no_contrast_failures("/")
    end

    test "the programs list clears AA", %{session: session} do
      insert(:program_schema, title: "Youth Fitness Basics")

      session
      |> visit("/programs")
      |> assert_no_contrast_failures("/programs")
    end
  end

  describe "authenticated surfaces" do
    test "the provider dashboard clears AA", %{session: session} do
      user = user_fixture(%{intended_roles: [:provider]}) |> set_password()
      # The provider role is resolved from this row, not from :intended_roles —
      # without it the route redirects and the audit measures the wrong page.
      insert(:provider_profile_schema, identity_id: user.id)

      session =
        session
        |> log_in(user)
        |> visit("/provider/dashboard")

      # A plain user_fixture/0 has no provider role, so this route redirects and
      # the audit silently measures the marketing home page instead — green, and
      # never once looking at the cream provider shell it exists to cover.
      assert String.ends_with?(Wallaby.Browser.current_url(session), "/provider/dashboard"),
             "expected to land on the provider dashboard, got #{Wallaby.Browser.current_url(session)}"

      assert_no_contrast_failures(session, "/provider/dashboard")
    end
  end
end
