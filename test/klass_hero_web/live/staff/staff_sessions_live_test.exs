defmodule KlassHeroWeb.Staff.StaffSessionsLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.EventTestHelper
  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.Participation
  alias KlassHero.Participation.Domain.Events.ParticipationEvents

  describe "authentication and authorization" do
    test "redirects unauthenticated users to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/staff/sessions")
      assert path =~ "/users/log-in"
    end

    test "redirects non-staff users to home", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/staff/sessions")
    end
  end

  describe "sessions page" do
    setup :register_and_log_in_staff

    test "renders page with staff-sessions container and date selector", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      assert has_element?(view, "#staff-sessions")
      assert has_element?(view, "#date-select")

      # The form id is what the client recovers the date by on reconnect. Pinned here so it
      # survives independently of config/test.exs's missing_form_id: :raise gate.
      assert has_element?(view, "form#date-select-form[phx-change=change_date]")
    end

    test "names each session's program and shows how many children are enrolled", %{
      conn: conn,
      provider: provider
    } do
      program = insert(:program_schema, provider_id: provider.id, category: "sports")

      insert(:program_listing_schema,
        id: program.id,
        provider_id: provider.id,
        category: "sports",
        title: "Soccer Training"
      )

      session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          status: :scheduled
        )

      {child, _parent} = insert_child_with_guardian()
      insert(:participation_record_schema, session_id: session.id, child_id: child.id)

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      assert has_element?(view, "h3", "Soccer Training")
      assert has_element?(view, "span", "1 child enrolled")
    end

    test "an event for another date does not inject that session into today's list", %{
      conn: conn,
      provider: provider
    } do
      # A schedule edit cancels every orphaned date at once and an enrolment seeds
      # every upcoming roster, so session events routinely concern other days.
      program = insert(:program_schema, provider_id: provider.id, category: "sports")

      insert(:program_listing_schema,
        id: program.id,
        provider_id: provider.id,
        category: "sports",
        title: "Soccer Training"
      )

      future =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.add(Date.utc_today(), 21),
          status: :scheduled
        )

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")
      refute has_element?(view, "button[phx-value-session_id='#{future.id}']")

      send(view.pid, {:session_changed, future.id})

      refute has_element?(view, "button[phx-value-session_id='#{future.id}']")
    end

    test "shows only assigned program sessions (matching staff tags)", %{
      conn: conn,
      provider: provider
    } do
      # Assigned program: category matches staff tag "sports"
      assigned_program = insert(:program_schema, provider_id: provider.id, category: "sports")

      _assigned_listing =
        insert(:program_listing_schema,
          id: assigned_program.id,
          provider_id: provider.id,
          category: "sports",
          title: "Soccer Training"
        )

      assigned_session =
        insert(:program_session_schema,
          program_id: assigned_program.id,
          session_date: Date.utc_today(),
          status: :scheduled
        )

      # Unassigned program: category does NOT match staff tags
      unassigned_program = insert(:program_schema, provider_id: provider.id, category: "arts")

      _unassigned_listing =
        insert(:program_listing_schema,
          id: unassigned_program.id,
          provider_id: provider.id,
          category: "arts",
          title: "Art Workshop"
        )

      unassigned_session =
        insert(:program_session_schema,
          program_id: unassigned_program.id,
          session_date: Date.utc_today(),
          status: :scheduled
        )

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      # Staff with tags: ["sports"] should see the sports session but not arts
      # The assigned session should show a Start Session button
      assert has_element?(view, "button", "Start Session")

      # Verify only the assigned session's button is present, not the unassigned one
      assert has_element?(
               view,
               "button[phx-value-session_id='#{assigned_session.id}']",
               "Start Session"
             )

      refute has_element?(
               view,
               "button[phx-value-session_id='#{unassigned_session.id}']",
               "Start Session"
             )
    end

    test "filters sessions by program_id query param", %{
      conn: conn,
      provider: provider
    } do
      program_a = insert(:program_schema, provider_id: provider.id, category: "sports")

      _listing_a =
        insert(:program_listing_schema,
          id: program_a.id,
          provider_id: provider.id,
          category: "sports",
          title: "Soccer"
        )

      _session_a =
        insert(:program_session_schema,
          program_id: program_a.id,
          session_date: Date.utc_today(),
          status: :scheduled
        )

      program_b = insert(:program_schema, provider_id: provider.id, category: "sports")

      _listing_b =
        insert(:program_listing_schema,
          id: program_b.id,
          provider_id: provider.id,
          category: "sports",
          title: "Basketball"
        )

      _session_b =
        insert(:program_session_schema,
          program_id: program_b.id,
          session_date: Date.utc_today(),
          status: :in_progress
        )

      # Visit with program_id filter for program_a only
      {:ok, view, _html} = live(conn, ~p"/staff/sessions?program_id=#{program_a.id}")

      # Should show Start Session (program_a is :scheduled)
      assert has_element?(view, "button", "Start Session")
      # Should NOT show Manage Participation (that's program_b which is :in_progress)
      refute has_element?(view, "a", "Manage Participation")
    end

    test "shows Start Session button for scheduled sessions", %{
      conn: conn,
      provider: provider
    } do
      program = insert(:program_schema, provider_id: provider.id, category: "sports")

      _listing =
        insert(:program_listing_schema,
          id: program.id,
          provider_id: provider.id,
          category: "sports"
        )

      _session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          status: :scheduled
        )

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      assert has_element?(view, "button", "Start Session")
    end

    test "shows Manage Participation link for in_progress sessions", %{
      conn: conn,
      provider: provider
    } do
      program = insert(:program_schema, provider_id: provider.id, category: "sports")

      _listing =
        insert(:program_listing_schema,
          id: program.id,
          provider_id: provider.id,
          category: "sports"
        )

      _session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          status: :in_progress
        )

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      assert has_element?(view, "a", "Manage Participation")
      assert has_element?(view, "button", "Complete Session")
    end

    test "shows View Participation link for completed sessions", %{
      conn: conn,
      provider: provider
    } do
      program = insert(:program_schema, provider_id: provider.id, category: "sports")

      _listing =
        insert(:program_listing_schema,
          id: program.id,
          provider_id: provider.id,
          category: "sports"
        )

      _session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          status: :completed
        )

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      assert has_element?(view, "a", "View Participation")
    end
  end

  describe "date filtering" do
    setup :register_and_log_in_staff

    test "changing date reloads sessions for that date", %{conn: conn, provider: provider} do
      program = insert(:program_schema, provider_id: provider.id, category: "sports")

      _listing =
        insert(:program_listing_schema,
          id: program.id,
          provider_id: provider.id,
          category: "sports"
        )

      tomorrow = Date.add(Date.utc_today(), 1)

      _session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: tomorrow,
          status: :scheduled
        )

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      # Initially no sessions today
      refute has_element?(view, "button", "Start Session")

      # Change to tomorrow
      render_change(view, "change_date", %{"date" => Date.to_iso8601(tomorrow)})

      assert has_element?(view, "button", "Start Session")
    end

    test "invalid date format shows error flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      render_change(view, "change_date", %{"date" => "not-a-date"})

      assert_flash(view, :error, "Invalid date format")
    end
  end

  describe "session actions" do
    setup :register_and_log_in_staff

    test "start_session transitions scheduled session to in_progress", %{
      conn: conn,
      provider: provider
    } do
      program = insert(:program_schema, provider_id: provider.id, category: "sports")

      _listing =
        insert(:program_listing_schema,
          id: program.id,
          provider_id: provider.id,
          category: "sports"
        )

      session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          status: :scheduled
        )

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      view
      |> element("button[phx-value-session_id='#{session.id}']", "Start Session")
      |> render_click()

      # Verify persistence - session transitioned in DB
      {:ok, %{session: updated}} = Participation.get_session_with_roster(session.id)
      assert updated.status == :in_progress

      assert_flash(view, :info, "Session started successfully")
    end

    test "complete_session transitions in_progress session to completed", %{
      conn: conn,
      provider: provider
    } do
      program = insert(:program_schema, provider_id: provider.id, category: "sports")

      _listing =
        insert(:program_listing_schema,
          id: program.id,
          provider_id: provider.id,
          category: "sports"
        )

      session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          status: :in_progress
        )

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      view
      |> element("button[phx-value-session_id='#{session.id}']", "Complete Session")
      |> render_click()

      # Verify persistence - session transitioned in DB
      {:ok, %{session: updated}} = Participation.get_session_with_roster(session.id)
      assert updated.status == :completed

      assert_flash(view, :info, "Session completed successfully")
    end

    test "rejects start_session for unassigned program", %{
      conn: conn,
      provider: provider
    } do
      # Create a program with category "arts" - not in staff tags ["sports"]
      unassigned_program = insert(:program_schema, provider_id: provider.id, category: "arts")

      _listing =
        insert(:program_listing_schema,
          id: unassigned_program.id,
          provider_id: provider.id,
          category: "arts"
        )

      session =
        insert(:program_session_schema,
          program_id: unassigned_program.id,
          session_date: Date.utc_today(),
          status: :scheduled
        )

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      # Attempt to start a session for an unassigned program via direct event
      render_hook(view, "start_session", %{"session_id" => session.id})

      assert_flash(view, :error, "Unauthorized")
    end
  end

  describe "does not show create session button" do
    setup :register_and_log_in_staff

    test "staff sessions page has no Create Session button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      refute has_element?(view, "a", "Create Session")
      refute has_element?(view, "button", "Create Session")
    end
  end
end
