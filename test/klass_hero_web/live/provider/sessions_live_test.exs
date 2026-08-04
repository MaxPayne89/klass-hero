defmodule KlassHeroWeb.Provider.SessionsLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.Participation

  describe "authentication and authorization" do
    test "redirects unauthenticated users to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/provider/sessions")
      assert path =~ "/users/log-in"
    end

    test "redirects non-provider users to home", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/provider/sessions")
    end
  end

  describe "sessions page" do
    setup :register_and_log_in_provider

    test "renders page title and date selector", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      assert has_element?(view, "h2", "My Sessions")
      assert has_element?(view, "#date-select")

      # The form id is what the client recovers the date by on reconnect. Pinned here so it
      # survives independently of config/test.exs's missing_form_id: :raise gate.
      assert has_element?(view, "form#date-select-form[phx-change=change_date]")
    end

    test "shows empty state when no sessions scheduled for today", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      refute has_element?(view, "button", "Start Session")
      refute has_element?(view, "button", "Complete Session")
      refute has_element?(view, "a", "Manage Participation")
    end

    test "shows sessions for today belonging to the provider", %{conn: conn, provider: provider} do
      program = insert(:program_schema, provider_id: provider.id)

      insert(:program_session_schema,
        program_id: program.id,
        session_date: Date.utc_today(),
        status: :scheduled
      )

      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      assert has_element?(view, "button", "Start Session")
    end

    test "names each session's program so a day's cards are distinguishable", %{
      conn: conn,
      provider: provider
    } do
      # Generating a term produces many same-shaped cards on one day; without the
      # program name they all read alike and a provider cannot tell them apart.
      for {title, start_time, end_time} <- [
            {"Junior Choir", ~T[09:00:00], ~T[10:00:00]},
            {"Piano for Beginners", ~T[15:00:00], ~T[16:00:00]}
          ] do
        program = insert(:program_schema, provider_id: provider.id, title: title)
        # Titles reach the page through the ProviderPrograms read model, not `programs`.
        insert(:program_listing_schema, id: program.id, provider_id: provider.id, title: title)

        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          start_time: start_time,
          end_time: end_time,
          status: :scheduled
        )
      end

      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      assert has_element?(view, "h3", "Junior Choir")
      assert has_element?(view, "h3", "Piano for Beginners")

      # Generated sessions carry no location, so the placeholder has to render
      # rather than leaving a bare map-pin icon.
      assert has_element?(view, "span", "Location TBD")
    end

    test "shows how many children are on each session's roster", %{conn: conn, provider: provider} do
      program = insert(:program_schema, provider_id: provider.id, title: "Junior Choir")
      insert(:program_listing_schema, id: program.id, provider_id: provider.id, title: "Junior Choir")

      session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          status: :scheduled
        )

      for _ <- 1..2 do
        {child, _parent} = insert_child_with_guardian()
        insert(:participation_record_schema, session_id: session.id, child_id: child.id)
      end

      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      assert has_element?(view, "span", "2 children enrolled")
    end

    test "does not show sessions for other providers", %{conn: conn} do
      other_provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: other_provider.id)

      insert(:program_session_schema,
        program_id: program.id,
        session_date: Date.utc_today(),
        status: :scheduled
      )

      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      refute has_element?(view, "button", "Start Session")
      refute has_element?(view, "button", "Complete Session")
      refute has_element?(view, "a", "Manage Participation")
    end

    test "shows 'Manage Participation' link for in_progress sessions", %{
      conn: conn,
      provider: provider
    } do
      program = insert(:program_schema, provider_id: provider.id)

      insert(:program_session_schema,
        program_id: program.id,
        session_date: Date.utc_today(),
        status: :in_progress
      )

      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      assert has_element?(view, "a", "Manage Participation")
      assert has_element?(view, "button", "Complete Session")
    end

    test "shows 'View Participation' link for completed sessions", %{
      conn: conn,
      provider: provider
    } do
      program = insert(:program_schema, provider_id: provider.id)

      insert(:program_session_schema,
        program_id: program.id,
        session_date: Date.utc_today(),
        status: :completed
      )

      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      assert has_element?(view, "a", "View Participation")
    end
  end

  describe "date filtering" do
    setup :register_and_log_in_provider

    test "changing date reloads sessions for that date", %{conn: conn, provider: provider} do
      program = insert(:program_schema, provider_id: provider.id)
      tomorrow = Date.add(Date.utc_today(), 1)

      insert(:program_session_schema,
        program_id: program.id,
        session_date: tomorrow,
        status: :scheduled
      )

      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      # Initially no sessions today
      refute has_element?(view, "button", "Start Session")

      # Change to tomorrow
      render_change(view, "change_date", %{"date" => Date.to_iso8601(tomorrow)})

      assert has_element?(view, "button", "Start Session")
    end

    test "invalid date format shows error flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      render_change(view, "change_date", %{"date" => "not-a-date"})

      assert_flash(view, :error, "Invalid date format")
    end
  end

  describe "PubSub real-time updates" do
    setup :register_and_log_in_provider

    test "updates session in stream when session_started event received", %{
      conn: conn,
      provider: provider
    } do
      program = insert(:program_schema, provider_id: provider.id)
      # Need listing so mount can build provider_program_ids MapSet
      _listing = insert(:program_listing_schema, id: program.id, provider_id: provider.id)

      session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          status: :scheduled
        )

      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      # Session initially shows Start button
      assert has_element?(view, "button", "Start Session")

      # Transition the session in DB so the re-fetch picks it up
      {:ok, _} = Participation.start_session(session.id)

      send(view.pid, {:session_changed, session.id})

      # After PubSub update, should show in_progress actions
      assert has_element?(view, "a", "Manage Participation")
    end

    test "refreshes session in stream when roster_seeded event received", %{
      conn: conn,
      provider: provider
    } do
      program = insert(:program_schema, provider_id: provider.id)
      _listing = insert(:program_listing_schema, id: program.id, provider_id: provider.id)

      session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          status: :scheduled
        )

      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      # Session initially visible
      assert has_element?(view, "button", "Start Session")

      send(view.pid, {:session_changed, session.id})

      # Session still present in the stream afterwards (no crash)
      assert has_element?(view, "button", "Start Session")
    end
  end

  describe "create session modal" do
    setup :register_and_log_in_provider

    test "navigating to /provider/sessions/new shows modal", %{conn: conn, provider: provider} do
      _listing = insert(:program_listing_schema, provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/provider/sessions/new")

      assert has_element?(view, "#create-session-modal")
      assert has_element?(view, "#create-session-form")
    end

    test "navigating back to /provider/sessions hides modal", %{conn: conn, provider: provider} do
      _listing = insert(:program_listing_schema, provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/provider/sessions/new")
      assert has_element?(view, "#create-session-modal")

      view |> element("#create-session-backdrop") |> render_click()
      refute has_element?(view, "#create-session-modal")
    end

    test "create session form shows provider's programs in dropdown", %{
      conn: conn,
      provider: provider
    } do
      listing =
        insert(:program_listing_schema,
          provider_id: provider.id,
          title: "Art Workshop"
        )

      _program =
        insert(:program_schema, id: listing.id, provider_id: provider.id, title: "Art Workshop")

      {:ok, view, _html} = live(conn, ~p"/provider/sessions/new")

      assert has_element?(view, "option", "Art Workshop")
    end

    test "create session form shows date, time, location, notes, and capacity fields", %{
      conn: conn,
      provider: provider
    } do
      _listing = insert(:program_listing_schema, provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/provider/sessions/new")

      assert has_element?(view, ~s(input[name="session[session_date]"]))
      assert has_element?(view, ~s(input[name="session[start_time]"]))
      assert has_element?(view, ~s(input[name="session[end_time]"]))
      assert has_element?(view, ~s(input[name="session[location]"]))
      assert has_element?(view, ~s(textarea[name="session[notes]"]))
      assert has_element?(view, ~s(input[name="session[max_capacity]"]))
    end
  end

  describe "program pre-fill" do
    setup :register_and_log_in_provider

    test "selecting a program pre-fills start_time, end_time, and location", %{
      conn: conn,
      provider: provider
    } do
      listing =
        insert(:program_listing_schema,
          provider_id: provider.id,
          title: "Art Workshop",
          meeting_start_time: ~T[09:00:00],
          meeting_end_time: ~T[11:30:00],
          location: "Room 101"
        )

      _program = insert(:program_schema, id: listing.id, provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/provider/sessions/new")

      # Select the program — triggers validate_session with pre-fill
      render_change(view, "validate_session", %{
        "session" => %{
          "program_id" => listing.id,
          "session_date" => Date.to_iso8601(Date.utc_today()),
          "start_time" => "",
          "end_time" => "",
          "location" => "",
          "notes" => "",
          "max_capacity" => ""
        }
      })

      # Verify pre-filled values in form inputs
      assert has_element?(view, ~s(input[name="session[start_time]"][value="09:00"]))
      assert has_element?(view, ~s(input[name="session[end_time]"][value="11:30"]))
      assert has_element?(view, ~s(input[name="session[location]"][value="Room 101"]))
    end

    test "selecting a program does not overwrite already-filled fields", %{
      conn: conn,
      provider: provider
    } do
      listing =
        insert(:program_listing_schema,
          provider_id: provider.id,
          title: "Art Workshop",
          meeting_start_time: ~T[09:00:00],
          meeting_end_time: ~T[11:30:00],
          location: "Room 101"
        )

      _program = insert(:program_schema, id: listing.id, provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/provider/sessions/new")

      # Select the program with already-filled start_time — should not overwrite
      render_change(view, "validate_session", %{
        "session" => %{
          "program_id" => listing.id,
          "session_date" => Date.to_iso8601(Date.utc_today()),
          "start_time" => "10:00",
          "end_time" => "",
          "location" => "",
          "notes" => "",
          "max_capacity" => ""
        }
      })

      # start_time should keep the provider's value, not the program default
      assert has_element?(view, ~s(input[name="session[start_time]"][value="10:00"]))
      # end_time and location should be pre-filled from program
      assert has_element?(view, ~s(input[name="session[end_time]"][value="11:30"]))
      assert has_element?(view, ~s(input[name="session[location]"][value="Room 101"]))
    end
  end

  describe "save_session" do
    setup :register_and_log_in_provider

    test "creates session and closes modal on valid submission", %{
      conn: conn,
      provider: provider
    } do
      listing =
        insert(:program_listing_schema,
          provider_id: provider.id,
          title: "Art Workshop"
        )

      program = insert(:program_schema, id: listing.id, provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/provider/sessions/new")

      view
      |> form("#create-session-form", %{
        "session" => %{
          "program_id" => program.id,
          "session_date" => Date.to_iso8601(Date.utc_today()),
          "start_time" => "09:00",
          "end_time" => "11:00",
          "location" => "Room 101",
          "notes" => "",
          "max_capacity" => "20"
        }
      })
      |> render_submit()

      # Modal should close (redirects to :index)
      refute has_element?(view, "#create-session-modal")

      assert_flash(view, :info, "Session created successfully")
    end

    test "rejects session creation for program not owned by provider", %{
      conn: conn,
      provider: provider
    } do
      # Need at least one listing for the provider so the form renders
      _listing = insert(:program_listing_schema, provider_id: provider.id)

      other_provider = insert(:provider_profile_schema)
      other_program = insert(:program_schema, provider_id: other_provider.id)

      {:ok, view, _html} = live(conn, ~p"/provider/sessions/new")

      # Trigger: bypass LiveViewTest select validation to simulate form tampering
      # Why: the dropdown only shows provider's own programs, but a malicious client
      #      could submit a program_id not in the dropdown
      # Outcome: server-side ownership check rejects the request
      render_submit(view, "save_session", %{
        "session" => %{
          "program_id" => other_program.id,
          "session_date" => Date.to_iso8601(Date.utc_today()),
          "start_time" => "09:00",
          "end_time" => "11:00"
        }
      })

      assert_flash(view, :error, "Unauthorized")
    end

    test "shows error for invalid time range", %{conn: conn, provider: provider} do
      listing = insert(:program_listing_schema, provider_id: provider.id)
      _program = insert(:program_schema, id: listing.id, provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/provider/sessions/new")

      view
      |> form("#create-session-form", %{
        "session" => %{
          "program_id" => listing.id,
          "session_date" => Date.to_iso8601(Date.utc_today()),
          "start_time" => "14:00",
          "end_time" => "10:00"
        }
      })
      |> render_submit()

      # Should stay on modal with error
      assert has_element?(view, "#create-session-modal")
      assert_flash(view, :error, "End time must be after start time")
    end
  end

  describe "session_created PubSub date filtering" do
    setup :register_and_log_in_provider

    test "created session appears in stream for the selected date", %{
      conn: conn,
      provider: provider
    } do
      listing =
        insert(:program_listing_schema,
          provider_id: provider.id,
          title: "Art Workshop"
        )

      program = insert(:program_schema, id: listing.id, provider_id: provider.id)

      session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          status: :scheduled
        )

      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      # Simulate PubSub event for a session created today
      send(view.pid, {:session_changed, session.id})

      # Session for today should appear in stream
      assert has_element?(view, "button", "Start Session")
    end

    test "created session does NOT appear when viewing a different date", %{
      conn: conn,
      provider: provider
    } do
      listing = insert(:program_listing_schema, provider_id: provider.id)
      program = insert(:program_schema, id: listing.id, provider_id: provider.id)

      tomorrow = Date.add(Date.utc_today(), 1)

      # Insert session for tomorrow — it won't show up in today's mount
      session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: tomorrow,
          status: :scheduled
        )

      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      # Initially no sessions for today
      refute has_element?(view, "button", "Start Session")

      # Send a session_created event with tomorrow's date
      send(view.pid, {:session_changed, session.id})

      # Session is for tomorrow but we're viewing today — should NOT appear
      refute has_element?(view, "button", "Start Session")
    end

    test "cancelling a session on another date does not add it to today's list", %{
      conn: conn,
      provider: provider
    } do
      listing = insert(:program_listing_schema, provider_id: provider.id)
      program = insert(:program_schema, id: listing.id, provider_id: provider.id)
      tomorrow = Date.add(Date.utc_today(), 1)

      session =
        insert(:program_session_schema, program_id: program.id, session_date: tomorrow, status: :scheduled)

      {:ok, view, _html} = live(conn, ~p"/provider/sessions")
      refute has_element?(view, "button", "Start Session")

      # A schedule edit cancels every orphaned date at once, so this event routinely
      # concerns a day other than the one on screen.
      send(view.pid, {:session_changed, session.id})

      refute has_element?(view, "button", "Start Session")
    end

    test "an unrelated participation event does not crash the view", %{conn: conn, provider: provider} do
      listing = insert(:program_listing_schema, provider_id: provider.id)
      _program = insert(:program_schema, id: listing.id, provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      # Session notes reach the provider topic and this view renders no clause for
      # them — without a catch-all that is a FunctionClauseError.
      send(view.pid, :session_notes_changed)

      assert render(view) =~ "Select Date"
    end
  end

  describe "Create Session button" do
    setup :register_and_log_in_provider

    test "shows 'Create Session' button on sessions page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      assert has_element?(view, ~s(a[href="/provider/sessions/new"]), "Create Session")
    end
  end

  describe "session actions" do
    setup :register_and_log_in_provider

    test "start_session transitions scheduled session to in_progress", %{
      conn: conn,
      provider: provider
    } do
      program = insert(:program_schema, provider_id: provider.id)

      session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          status: :scheduled
        )

      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      view
      |> element("button[phx-value-session_id='#{session.id}']", "Start Session")
      |> render_click()

      # Verify persistence — session transitioned in DB
      {:ok, %{session: updated}} = Participation.get_session_with_roster(session.id)
      assert updated.status == :in_progress

      assert_flash(view, :info, "Session started successfully")
    end

    test "complete_session transitions in_progress session to completed", %{
      conn: conn,
      provider: provider
    } do
      program = insert(:program_schema, provider_id: provider.id)

      session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          status: :in_progress
        )

      {:ok, view, _html} = live(conn, ~p"/provider/sessions")

      view
      |> element("button[phx-value-session_id='#{session.id}']", "Complete Session")
      |> render_click()

      # Verify persistence — session transitioned in DB
      {:ok, %{session: updated}} = Participation.get_session_with_roster(session.id)
      assert updated.status == :completed

      assert_flash(view, :info, "Session completed successfully")
    end
  end
end
