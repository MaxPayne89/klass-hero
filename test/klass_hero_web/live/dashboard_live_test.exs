defmodule KlassHeroWeb.DashboardLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  alias KlassHero.AccountsFixtures
  alias KlassHero.Family.Child

  describe "DashboardLive (Phase 2.1 — Pa* component layout)" do
    setup :register_and_log_in_user

    test "renders dashboard page successfully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      render_async(view)

      # New surface anchors: kid picker, KPI grid, upcoming sessions card.
      assert has_element?(view, "#dashboard-stats")
      assert has_element?(view, "#upcoming-sessions")
      assert has_element?(view, "#messages-preview")
    end

    test "sidebar links to user settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      html = render_async(view)

      # parent_app layout's sidebar puts the account row at the bottom.
      assert html =~ "/users/settings"
    end

    test "topbar shows time-of-day greeting + 'Your week with the kids' subtitle", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      html = render_async(view)

      # New copy: subtitle is fixed; title contains a time-bucket greeting +
      # the user's first name (extracted from `user.name`).
      assert html =~ "Your week with the kids"
      refute html =~ "Your family this week"

      first_name = user.name |> String.split() |> List.first()
      assert html =~ first_name
      # One of the three buckets must always render.
      assert html =~ "Good morning" or html =~ "Good afternoon" or html =~ "Good evening"
    end

    test "renders the KPI grid with live counts (no Coming-soon placeholder on Messages)", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert html = render_async(view)
      assert html =~ "Active programs"
      assert html =~ "Upcoming this week"
      assert html =~ "Unread messages"

      # Messages card is live: numeric value renders, no Coming-soon pill.
      stats_html =
        view
        |> element("#dashboard-stats")
        |> render()

      refute stats_html =~ "Coming soon"
    end

    test "renders weekly goal card with the bundle's title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      html = render_async(view)

      assert html =~ "Weekly adventure goal"
    end

    test "renders kid-picker add button when no children yet", %{conn: conn} do
      # Default register_and_log_in_user does not create children, so the
      # kid-picker section is hidden. The add button (pa_kid_picker's "+")
      # is therefore not rendered — verify the section is absent rather
      # than asserting on its inner button.
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      render_async(view)

      refute has_element?(view, "#kid-picker")
    end

    test "upcoming sessions section renders an empty-state copy", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert render_async(view) =~ "No upcoming sessions"
    end

    test "recent messages preview renders an empty-state copy", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      html = render_async(view)

      assert html =~ "No messages yet."
    end

    test "renders latest message preview when the user has a conversation summary",
         %{conn: conn, user: user} do
      # Regression: #897 — dashboard crashed with `KeyError :body` because the
      # LiveView read `msg.body` while the read-model DTO exposes `:content`.
      preview_text = "Spring recital reminder for Saturday"

      insert(:conversation_summary_schema,
        user_id: user.id,
        latest_message_content: preview_text,
        latest_message_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert render_async(view) =~ preview_text
    end
  end

  describe "Contact Provider flow" do
    test "clicking contact_provider starts a conversation and navigates to it", %{conn: conn} do
      user = AccountsFixtures.user_fixture(intended_roles: [:parent])
      parent = insert(:parent_profile_schema, identity_id: user.id)
      owner = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: owner.id)
      program = insert(:program_schema, provider_id: provider.id)
      {child, _parent} = insert_child_with_guardian(parent: parent)

      insert(:enrollment_schema,
        parent_id: parent.id,
        program_id: program.id,
        child_id: child.id,
        status: "confirmed",
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      render_async(view)

      selector =
        ~s|button[phx-click="contact_provider"][phx-value-program-id="#{program.id}"]|

      assert {:error, {:live_redirect, %{to: path}}} =
               view |> element(selector) |> render_click()

      assert path =~ ~r"^/messages/[0-9a-f-]+$"
    end
  end

  describe "async loading (perf pass #1)" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(intended_roles: [:parent])
      parent = insert(:parent_profile_schema, identity_id: user.id)
      owner = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: owner.id)
      program = insert(:program_schema, provider_id: provider.id)
      {child, _parent} = insert_child_with_guardian(parent: parent)

      insert(:enrollment_schema,
        parent_id: parent.id,
        program_id: program.id,
        child_id: child.id,
        status: "confirmed",
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

      %{conn: log_in_user(conn, user), program: program}
    end

    test "disconnected render shows a loading skeleton, not the family data", %{conn: conn} do
      html = conn |> get(~p"/dashboard") |> html_response(200)

      assert html =~ ~s(id="family-programs-loading")
      refute html =~ ~s(id="family-programs-list")
    end

    test "connected mount loads family data via async (sourced from current_scope.parent)", %{
      conn: conn
    } do
      {:ok, view, _loading_html} = live(conn, ~p"/dashboard")

      # NB: the pre-async loading skeleton is asserted deterministically in the
      # disconnected-render test above. Asserting it here (before render_async)
      # races the assign_async task — on a fast/loaded runner the result lands
      # first, flaking both the "loading shown" and "list absent" checks. Only
      # the settled state is deterministic, so that's all we assert here.
      render_async(view)

      assert has_element?(view, "#family-programs-list")
      assert has_element?(view, "#kid-picker")
      refute has_element?(view, "#family-programs-loading")
    end

    test "upcoming sessions tile renders a future session (was always empty before the batch fix)",
         %{conn: conn, program: program} do
      insert(:program_session_schema,
        program_id: program.id,
        session_date: Date.add(Date.utc_today(), 3)
      )

      {:ok, view, _html} = live(conn, ~p"/dashboard")
      render_async(view)

      upcoming = view |> element("#upcoming-sessions") |> render()

      refute upcoming =~ "No upcoming sessions"
      assert upcoming =~ program.title
    end
  end

  describe "upcoming sessions fan-out (perf pass #2)" do
    test "a session in a program shared by two children renders one row per child", %{conn: conn} do
      user = AccountsFixtures.user_fixture(intended_roles: [:parent])
      parent = insert(:parent_profile_schema, identity_id: user.id)
      owner = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: owner.id)
      program = insert(:program_schema, provider_id: provider.id)

      {child_a, _} = insert_child_with_guardian(parent: parent, first_name: "Ada", last_name: "Alpha")
      {child_b, _} = insert_child_with_guardian(parent: parent, first_name: "Ben", last_name: "Beta")

      for child <- [child_a, child_b] do
        insert(:enrollment_schema,
          parent_id: parent.id,
          program_id: program.id,
          child_id: child.id,
          status: "confirmed",
          confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )
      end

      insert(:program_session_schema, program_id: program.id, session_date: Date.add(Date.utc_today(), 2))

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      render_async(view)

      upcoming = view |> element("#upcoming-sessions") |> render()

      assert upcoming =~ Child.full_name(child_a)
      assert upcoming =~ Child.full_name(child_b)
    end
  end

  describe "role-based redirect from /dashboard" do
    test "staff user is redirected to /staff/dashboard", %{} do
      user = KlassHero.AccountsFixtures.user_fixture(intended_roles: [:staff])
      provider = provider_profile_fixture()

      staff_member_fixture(%{
        provider_id: provider.id,
        user_id: user.id,
        active: true,
        invitation_status: :accepted
      })

      conn = build_conn() |> log_in_user(user)
      assert {:error, {:redirect, %{to: "/staff/dashboard"}}} = live(conn, ~p"/dashboard")
    end
  end
end
