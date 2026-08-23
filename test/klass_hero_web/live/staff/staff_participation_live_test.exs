defmodule KlassHeroWeb.Staff.StaffParticipationLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.Accounts.Scope
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Participation.SessionNote
  alias KlassHero.ProviderFixtures
  alias KlassHero.Repo

  describe "authentication and authorization" do
    test "redirects unauthenticated users to login", %{conn: conn} do
      session_id = Ecto.UUID.generate()

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/staff/participation/#{session_id}")

      assert path =~ "/users/log-in"
    end

    test "redirects non-staff users to home", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      session_id = Ecto.UUID.generate()

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn, ~p"/staff/participation/#{session_id}")
    end

    test "redirects to /staff/sessions when session belongs to unassigned program", %{conn: conn} do
      %{conn: conn, provider: provider} = register_and_log_in_staff(%{conn: conn})

      # Category "sports" matches the staff member's Specialties on purpose. What makes
      # this program unreachable is the absence of a Program Staff Assignment (#1323) —
      # before which a matching category alone would have opened the roster.
      unassigned_program = insert(:program_schema, provider_id: provider.id, category: "sports")

      _listing =
        insert(:program_listing_schema,
          id: unassigned_program.id,
          provider_id: provider.id,
          category: "sports",
          title: "Soccer Training"
        )

      session =
        insert(:program_session_schema,
          program_id: unassigned_program.id,
          session_date: Date.utc_today(),
          status: :in_progress
        )

      assert {:error, {:live_redirect, %{to: "/staff/sessions"}}} =
               live(conn, ~p"/staff/participation/#{session.id}")
    end

    test "redirects a staff member off a Closed Program's roster, saying why (#1082)", %{conn: conn} do
      %{conn: conn, provider: provider, staff: staff} = register_and_log_in_staff(%{conn: conn})

      closed =
        insert(:program_schema,
          provider_id: provider.id,
          category: "sports",
          end_date: Date.add(Date.utc_today(), -20)
        )

      ProviderFixtures.program_assignment_fixture(%{
        provider_id: provider.id,
        program_id: closed.id,
        staff_member_id: staff.id
      })

      session =
        insert(:program_session_schema,
          program_id: closed.id,
          session_date: Date.add(Date.utc_today(), -25),
          status: :completed
        )

      assert {:error, {:live_redirect, %{to: "/staff/sessions", flash: flash}}} =
               live(conn, ~p"/staff/participation/#{session.id}")

      assert flash["error"] =~ "This program has closed"
    end

    test "opens the roster for a session the staff member covers without the program", %{conn: conn} do
      %{conn: conn, provider: provider, staff: staff} = register_and_log_in_staff(%{conn: conn})
      session = session_in_new_program(provider)

      assert {:ok, _} =
               KlassHero.Provider.assign_staff_to_session(%{
                 provider_id: provider.id,
                 session_id: session.id,
                 staff_member_id: staff.id
               })

      {:ok, view, _html} = live(conn, ~p"/staff/participation/#{session.id}")

      assert has_element?(view, "#staff-participation")
    end

    test "redirects a staff member taken off the session, though still on the program", %{conn: conn} do
      %{conn: conn, provider: provider, staff: staff} = register_and_log_in_staff(%{conn: conn})
      session = session_in_new_program(provider)

      for member <- [staff, ProviderFixtures.staff_member_fixture(%{provider_id: provider.id})] do
        ProviderFixtures.program_assignment_fixture(%{
          provider_id: provider.id,
          program_id: session.program_id,
          staff_member_id: member.id
        })
      end

      assert {:ok, _} =
               KlassHero.Provider.unassign_staff_from_session(session.id, staff.id, provider.id)

      assert {:error, {:live_redirect, %{to: "/staff/sessions"}}} =
               live(conn, ~p"/staff/participation/#{session.id}")
    end
  end

  defp session_in_new_program(provider) do
    program = insert(:program_schema, provider_id: provider.id, category: "sports")

    _listing =
      insert(:program_listing_schema,
        id: program.id,
        provider_id: provider.id,
        category: "sports",
        title: "Soccer Training"
      )

    insert(:program_session_schema,
      program_id: program.id,
      session_date: Date.utc_today(),
      status: :in_progress
    )
  end

  describe "participation management" do
    setup :register_and_log_in_staff

    setup %{provider: provider, staff: staff, user: user} do
      program = insert(:program_schema, provider_id: provider.id, category: "sports")

      _listing =
        insert(:program_listing_schema,
          id: program.id,
          provider_id: provider.id,
          category: "sports",
          title: "Soccer Training"
        )

      # The assignment is what lets this staff member manage the session (#1323) —
      # their matching Specialty does not.
      ProviderFixtures.program_assignment_fixture(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_member_id: staff.id
      })

      session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          status: :in_progress
        )

      parent = insert(:parent_profile_schema)

      {child, _parent} =
        insert_child_with_guardian(
          parent: parent,
          first_name: "Lina",
          last_name: "Schmidt"
        )

      record =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          parent_id: parent.id,
          status: :registered
        )

      # The same scope the LiveView acts under, so arranging a check-in directly
      # through the context goes down the production authorization path.
      scope = %Scope{user: user, staff_member: staff}

      %{session: session, parent: parent, child: child, record: record, program: program, scope: scope}
    end

    test "offers Complete Session while the session is in progress", %{conn: conn, session: session} do
      {:ok, view, _html} = live(conn, ~p"/staff/participation/#{session.id}")

      assert has_element?(view, "#complete-session-btn")
    end

    # One handler serves both surfaces, so this proves the staff wiring reaches
    # it — not that the absence logic works, which `record_absence_test.exs` owns.
    test "a staff member can mark a child absent with a reason", %{
      conn: conn,
      session: session,
      record: record
    } do
      {:ok, view, _html} = live(conn, ~p"/staff/participation/#{session.id}")

      view |> element("#mark-absent-btn-#{record.id}") |> render_click()

      view
      |> form("#absence-form-#{record.id}", %{"absence" => %{"content" => "Dentist appointment"}})
      |> render_submit()

      assert_flash(view, :info, "Child marked absent")
      assert Repo.get!(ParticipationRecord, record.id).status == :absent
      assert render(view) =~ "Dentist appointment"
    end

    # Defect 4, on the staff roster too.
    test "an absent row offers a late arrival instead of a dead Check In", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      {:ok, _} = KlassHero.Participation.record_absence(scope, record.id, reason: "No-show")

      {:ok, view, _html} = live(conn, ~p"/staff/participation/#{session.id}")

      refute has_element?(view, "#mark-absent-btn-#{record.id}")

      view
      |> element("button[phx-click='check_in'][phx-value-id='#{record.id}']")
      |> render_click()

      assert Repo.get!(ParticipationRecord, record.id).status == :checked_in
    end

    test "completing absents the stragglers and locks the roster", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      {:ok, _} = KlassHero.Participation.record_check_in(scope, record.id)

      {:ok, view, _html} = live(conn, ~p"/staff/participation/#{session.id}")
      assert has_element?(view, "#edit-btn-#{record.id}")

      view |> element("#complete-session-btn") |> render_click()

      assert_flash(view, :info, "Session completed successfully")
      assert Repo.get!(ProgramSession, session.id).status == :completed
      refute has_element?(view, "#complete-session-btn")
      refute has_element?(view, "#edit-btn-#{record.id}")
    end

    test "renders staff-participation element and child names in roster", %{
      conn: conn,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/staff/participation/#{session.id}")

      assert has_element?(view, "#staff-participation")
      assert has_element?(view, "div", "Lina")
      assert has_element?(view, "div", "Schmidt")
    end

    test "page renders exactly one <h1> (the page header owns it)", %{
      conn: conn,
      session: session
    } do
      {:ok, view, _html} = live(conn, ~p"/staff/participation/#{session.id}")

      # Render after mount so @session is loaded. The single top-level heading is
      # the <.page_header> title; the shared provider_app topbar no longer emits
      # an <h1>. See #984. No element/2 equivalent for "exactly one of X", so we
      # count tag openings directly.
      html = render(view)
      h1_count = length(String.split(html, "<h1")) - 1

      assert h1_count == 1
    end

    test "check_in succeeds and shows flash", %{
      conn: conn,
      session: session,
      record: record
    } do
      {:ok, view, _html} = live(conn, ~p"/staff/participation/#{session.id}")

      assert has_element?(view, "button[phx-click='check_in'][phx-value-id='#{record.id}']")

      view
      |> element("button[phx-click='check_in'][phx-value-id='#{record.id}']")
      |> render_click()

      assert_flash(view, :info, "Child checked in successfully")

      # After check-in, should now show the Check Out button
      assert has_element?(
               view,
               "button[phx-click='expand_checkout_form'][phx-value-id='#{record.id}']"
             )
    end

    test "expand checkout form, confirm checkout succeeds", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      # Check in first
      {:ok, _} =
        KlassHero.Participation.record_check_in(scope, record.id)

      {:ok, view, _html} = live(conn, ~p"/staff/participation/#{session.id}")

      # Expand "Record departure" form
      view
      |> element("button[phx-click='expand_checkout_form'][phx-value-id='#{record.id}']")
      |> render_click()

      assert has_element?(view, "#checkout-form-#{record.id}")

      # Submit checkout
      view
      |> form("#checkout-form-#{record.id}", %{checkout: %{notes: "Picked up by parent"}})
      |> render_submit()

      assert_flash(view, :info, "Child checked out successfully")
      refute has_element?(view, "#checkout-form-#{record.id}")
    end

    test "shows Edit and 'Record departure' buttons for a checked-in child; pill reads Present",
         %{conn: conn, session: session, record: record, scope: scope} do
      {:ok, _} =
        KlassHero.Participation.record_check_in(scope, record.id)

      {:ok, view, html} = live(conn, ~p"/staff/participation/#{session.id}")

      assert has_element?(view, "#edit-btn-#{record.id}")

      assert has_element?(
               view,
               "button[phx-click='expand_checkout_form'][phx-value-id='#{record.id}']",
               "Record departure"
             )

      assert html =~ "Present"
      refute html =~ "Checked In"
    end

    test "submitting notes-only edit updates the check-in note", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      {:ok, _} =
        KlassHero.Participation.record_check_in(scope, record.id)

      {:ok, view, _html} = live(conn, ~p"/staff/participation/#{session.id}")

      view |> element("#edit-btn-#{record.id}") |> render_click()

      view
      |> form("#edit-record-form-#{record.id}", edit: %{notes: "Brought a snack"})
      |> render_submit()

      reloaded =
        KlassHero.Repo.get!(
          ParticipationRecord,
          record.id
        )

      assert reloaded.check_in_notes == "Brought a snack"
      refute has_element?(view, "#edit-record-form-#{record.id}")
    end

    test "submitting departure time records check-out via correct_attendance", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      {:ok, _} =
        KlassHero.Participation.record_check_in(scope, record.id)

      {:ok, view, _html} = live(conn, ~p"/staff/participation/#{session.id}")

      view |> element("#edit-btn-#{record.id}") |> render_click()

      # Pick a check-out time strictly after check_in_at (which was just set
      # to DateTime.utc_now/0). HTML datetime-local drops seconds, so we align
      # to minute precision to get an exact round-trip through the parser.
      expected_check_out =
        DateTime.utc_now()
        |> DateTime.add(60, :second)
        |> Map.merge(%{second: 0, microsecond: {0, 0}})

      form_value = Calendar.strftime(expected_check_out, "%Y-%m-%dT%H:%M")

      view
      |> form("#edit-record-form-#{record.id}",
        edit: %{notes: "Mum collected", check_out_at: form_value}
      )
      |> render_submit()

      reloaded =
        KlassHero.Repo.get!(
          ParticipationRecord,
          record.id
        )

      assert reloaded.status == :checked_out
      assert reloaded.check_out_at == expected_check_out
      assert reloaded.check_out_notes == "Mum collected"
    end

    test "submit_note with a record_id from another session is rejected", %{
      conn: conn,
      session: session,
      record: record,
      scope: scope
    } do
      {:ok, _} =
        KlassHero.Participation.record_check_in(scope, record.id)

      foreign_record = insert(:participation_record_schema)

      {:ok, view, _html} = live(conn, ~p"/staff/participation/#{session.id}")

      render_hook(view, "submit_note", %{
        "id" => to_string(foreign_record.id),
        "note" => %{"content" => "Should be blocked"}
      })

      assert_flash(view, :error, "Record not found")

      refute KlassHero.Repo.get_by(SessionNote,
               participation_record_id: foreign_record.id
             )
    end
  end
end
