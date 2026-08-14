defmodule KlassHeroWeb.Staff.StaffSessionsLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.Participation
  alias KlassHero.ProviderFixtures

  # `register_and_log_in_staff/1` gives the staff member `tags: ["sports"]`. That is
  # deliberate and inert: since #1323 Specialties describe a person and grant nothing,
  # so several tests below assign an "arts" program to prove a mismatched category no
  # longer hides anything, and leave a "sports" program unassigned to prove a matching
  # one no longer reveals anything.

  # A program this staff member works on: the write row ownership checks read, the
  # listing row the projection would maintain, and the assignment that decides
  # visibility.
  defp assigned_program(%{provider: provider, staff: staff}, attrs \\ []) do
    program = build_program(provider, attrs)

    ProviderFixtures.program_assignment_fixture(%{
      provider_id: provider.id,
      program_id: program.id,
      staff_member_id: staff.id
    })

    program
  end

  # Same rows, no assignment — the provider has this program, this staff member does not.
  defp unassigned_program(%{provider: provider}, attrs) do
    build_program(provider, attrs)
  end

  defp build_program(provider, attrs) do
    category = Keyword.get(attrs, :category, "sports")
    program = insert(:program_schema, provider_id: provider.id, category: category)

    insert(
      :program_listing_schema,
      Keyword.merge(
        [id: program.id, provider_id: provider.id, category: category],
        Keyword.take(attrs, [:title])
      )
    )

    program
  end

  defp session_on(program, date, status) do
    insert(:program_session_schema,
      program_id: program.id,
      session_date: date,
      status: status
    )
  end

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

    test "names each session's program and shows how many children are enrolled",
         %{conn: conn} = ctx do
      program = assigned_program(ctx, title: "Soccer Training")
      session = session_on(program, Date.utc_today(), :scheduled)

      {child, _parent} = insert_child_with_guardian()
      insert(:participation_record_schema, session_id: session.id, child_id: child.id)

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      assert has_element?(view, "h3", "Soccer Training")
      assert has_element?(view, "span", "1 child enrolled")
    end

    test "an event for another date does not inject that session into today's list",
         %{conn: conn} = ctx do
      # A schedule edit cancels every orphaned date at once and an enrolment seeds
      # every upcoming roster, so session events routinely concern other days.
      program = assigned_program(ctx, title: "Soccer Training")
      future = session_on(program, Date.add(Date.utc_today(), 21), :scheduled)

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")
      refute has_element?(view, "button[phx-value-session_id='#{future.id}']")

      send(view.pid, {:session_changed, future.id})

      refute has_element?(view, "button[phx-value-session_id='#{future.id}']")
    end

    test "shows sessions of assigned programs only, whatever the staff member's Specialties",
         %{conn: conn} = ctx do
      # Assigned but category-mismatched: visible anyway.
      assigned = assigned_program(ctx, category: "arts", title: "Art Workshop")
      assigned_session = session_on(assigned, Date.utc_today(), :scheduled)

      # Category-matched but unassigned: hidden anyway.
      unassigned = unassigned_program(ctx, category: "sports", title: "Soccer Training")
      unassigned_session = session_on(unassigned, Date.utc_today(), :scheduled)

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

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

    test "filters sessions by program_id query param", %{conn: conn} = ctx do
      program_a = assigned_program(ctx, title: "Soccer")
      session_on(program_a, Date.utc_today(), :scheduled)

      program_b = assigned_program(ctx, title: "Basketball")
      session_on(program_b, Date.utc_today(), :in_progress)

      # Visit with program_id filter for program_a only
      {:ok, view, _html} = live(conn, ~p"/staff/sessions?program_id=#{program_a.id}")

      # Should show Start Session (program_a is :scheduled)
      assert has_element?(view, "button", "Start Session")
      # Should NOT show Manage Participation (that's program_b which is :in_progress)
      refute has_element?(view, "a", "Manage Participation")
    end

    test "shows Start Session button for scheduled sessions", %{conn: conn} = ctx do
      ctx |> assigned_program() |> session_on(Date.utc_today(), :scheduled)

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      assert has_element?(view, "button", "Start Session")
    end

    test "shows Manage Participation link for in_progress sessions", %{conn: conn} = ctx do
      ctx |> assigned_program() |> session_on(Date.utc_today(), :in_progress)

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      assert has_element?(view, "a", "Manage Participation")
      assert has_element?(view, "button", "Complete Session")
    end

    test "shows View Participation link for completed sessions", %{conn: conn} = ctx do
      ctx |> assigned_program() |> session_on(Date.utc_today(), :completed)

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      assert has_element?(view, "a", "View Participation")
    end
  end

  describe "date filtering" do
    setup :register_and_log_in_staff

    test "changing date reloads sessions for that date", %{conn: conn} = ctx do
      tomorrow = Date.add(Date.utc_today(), 1)
      ctx |> assigned_program() |> session_on(tomorrow, :scheduled)

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

    test "start_session transitions scheduled session to in_progress", %{conn: conn} = ctx do
      session = ctx |> assigned_program() |> session_on(Date.utc_today(), :scheduled)

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      view
      |> element("button[phx-value-session_id='#{session.id}']", "Start Session")
      |> render_click()

      # Verify persistence - session transitioned in DB
      {:ok, %{session: updated}} = Participation.get_session_with_roster(session.id)
      assert updated.status == :in_progress

      assert_flash(view, :info, "Session started successfully")
    end

    test "complete_session transitions in_progress session to completed", %{conn: conn} = ctx do
      session = ctx |> assigned_program() |> session_on(Date.utc_today(), :in_progress)

      {:ok, view, _html} = live(conn, ~p"/staff/sessions")

      view
      |> element("button[phx-value-session_id='#{session.id}']", "Complete Session")
      |> render_click()

      # Verify persistence - session transitioned in DB
      {:ok, %{session: updated}} = Participation.get_session_with_roster(session.id)
      assert updated.status == :completed

      assert_flash(view, :info, "Session completed successfully")
    end

    test "rejects start_session for a program the staff member is not assigned to",
         %{conn: conn} = ctx do
      # Category "sports" matches the staff member's Specialties on purpose: a matching
      # Specialty must not authorize anything now that assignments decide access.
      session =
        ctx
        |> unassigned_program(category: "sports")
        |> session_on(Date.utc_today(), :scheduled)

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
