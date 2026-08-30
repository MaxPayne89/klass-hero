defmodule KlassHeroWeb.Admin.SessionsLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  describe "admin access control" do
    setup :register_and_log_in_admin

    test "admin can access /admin/sessions", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/sessions")
      assert html =~ "Sessions"
    end

    # @current_url comes from Backpex.InitAssigns' handle_params hook, attached in
    # the :admin_custom live_session. Nothing else asserts that hook is wired, so
    # dropping it from the router would otherwise surface as a runtime KeyError.
    test "highlights the Sessions sidebar item", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions")

      assert has_element?(view, ~s|a[href="/admin/sessions"].bg-neutral|)
      refute has_element?(view, ~s|a[href="/admin/emails"].bg-neutral|)
    end
  end

  describe "non-admin access" do
    setup :register_and_log_in_user

    test "non-admin is redirected", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/admin/sessions")

      assert flash["error"] =~ "access"
    end
  end

  describe "unified filter bar" do
    setup :register_and_log_in_admin

    setup do
      provider = insert(:provider_profile_schema, business_name: "Creative Learning Inc.")
      program = insert(:program_schema, provider_id: provider.id, title: "Art Adventures")

      session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          start_time: ~T[09:00:00],
          end_time: ~T[10:30:00],
          status: "in_progress"
        )

      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()
      {child, parent} = insert_child_with_guardian()

      insert(:participation_record_schema,
        session_id: session.id,
        child_id: child.id,
        parent_id: parent.id,
        status: :checked_in,
        check_in_at: DateTime.utc_now(),
        check_in_by: user.id
      )

      %{session: session, program: program, provider: provider}
    end

    test "displays sessions with program and provider names", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions")
      assert has_element?(view, "#sessions-list")
      assert render(view) =~ "Art Adventures"
      assert render(view) =~ "Creative Learning Inc."
    end

    test "shows attendance count", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/sessions")
      assert html =~ "1 / 1"
    end

    test "renders provider searchable select", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions")
      assert has_element?(view, "#provider-select")
    end

    test "renders program searchable select", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions")
      assert has_element?(view, "#program-select")
    end

    test "gives both searchable selects a recoverable search form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions")

      # Two instances on one page, so the derived ids must stay distinct.
      assert has_element?(view, "form#provider-select-search-form")
      assert has_element?(view, "form#program-select-search-form")
    end

    test "renders date inputs defaulting to today", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions")
      today = Date.utc_today() |> Date.to_iso8601()
      assert has_element?(view, "input[name=date_from][value='#{today}']")
      assert has_element?(view, "input[name=date_to][value='#{today}']")
    end

    test "renders status dropdown", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions")
      assert has_element?(view, "select[name=status]")
    end

    test "no mode switcher exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions")
      refute has_element?(view, "#mode-today")
      refute has_element?(view, "#mode-filter")
    end

    test "always shows session date in rows", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/sessions")
      today = Date.utc_today() |> Date.to_iso8601()
      assert html =~ today
    end

    test "filtering by status re-queries sessions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions")

      view
      |> element("#filter-bar")
      |> render_change(%{"status" => "completed"})

      # Session is in_progress, so filtering for completed should hide it
      refute render(view) =~ "Art Adventures"
    end

    test "filtering by date range excludes sessions outside range", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions")
      yesterday = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()

      view
      |> element("#filter-bar")
      |> render_change(%{"date_from" => yesterday, "date_to" => yesterday})

      # Session is today, so filtering for yesterday should hide it
      refute render(view) =~ "Art Adventures"
    end

    # Both dates are free-form inputs, so a decade-wide pair is one click away.
    # `list_session_summaries/1` raises past a year rather than loading the whole
    # table -- correct for the Schedule calendar, which derives its own range,
    # and a crash here if this surface did not narrow first.
    test "a range wider than a year is clamped rather than crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions")
      from = Date.utc_today() |> Date.add(-30) |> Date.to_iso8601()
      far = Date.utc_today() |> Date.add(3000) |> Date.to_iso8601()

      html =
        view
        |> element("#filter-bar")
        |> render_change(%{"date_from" => from, "date_to" => far})

      # Still serving the page, and saying it narrowed rather than doing it quietly.
      assert html =~ "Art Adventures"
      assert render(view) =~ "Narrow the range"
    end

    test "a year-wide range is left alone", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions")
      from = Date.utc_today() |> Date.add(-30) |> Date.to_iso8601()
      to = Date.utc_today() |> Date.add(300) |> Date.to_iso8601()

      html =
        view
        |> element("#filter-bar")
        |> render_change(%{"date_from" => from, "date_to" => to})

      assert html =~ "Art Adventures"
      refute html =~ "Narrow the range"
    end
  end

  describe "correction flow" do
    setup :register_and_log_in_admin

    setup do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      session =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.utc_today(),
          status: "in_progress"
        )

      {child, parent} = insert_child_with_guardian(first_name: "Emma")

      record =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          parent_id: parent.id,
          status: :checked_in,
          check_in_at: ~U[2026-03-13 09:00:00Z],
          check_in_by: user.id
        )

      %{session: session, record: record}
    end

    test "opens correction form for a record", %{conn: conn, session: session, record: record} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions/#{session.id}")

      view |> element("#correct-#{record.id}") |> render_click()
      assert has_element?(view, "#correction-form")
    end

    test "cancels correction", %{conn: conn, session: session, record: record} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions/#{session.id}")

      view |> element("#correct-#{record.id}") |> render_click()
      view |> element("#cancel-correction") |> render_click()
      refute has_element?(view, "#correction-form")
    end

    test "saves correction with reason", %{conn: conn, session: session, record: record} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions/#{session.id}")

      view |> element("#correct-#{record.id}") |> render_click()

      view
      |> form("#correction-form", %{
        correction: %{
          status: "checked_out",
          check_out_at: "2026-03-13T10:30",
          reason: "Provider forgot to check out"
        }
      })
      |> render_submit()

      assert render(view) =~ "corrected successfully"
    end

    test "shows error when reason is blank", %{conn: conn, session: session, record: record} do
      {:ok, view, _html} = live(conn, ~p"/admin/sessions/#{session.id}")

      view |> element("#correct-#{record.id}") |> render_click()

      view
      |> form("#correction-form", %{
        correction: %{status: "absent", reason: ""}
      })
      |> render_submit()

      assert render(view) =~ "reason"
    end
  end
end
