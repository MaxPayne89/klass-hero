defmodule KlassHeroWeb.Provider.ScheduleLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  setup :register_and_log_in_provider

  setup %{provider: provider} do
    program = insert(:program_schema, provider_id: provider.id, title: "Chess Club")

    session =
      insert(:program_session_schema,
        program_id: program.id,
        session_date: ~D[2026-08-19],
        start_time: ~T[15:00:00],
        end_time: ~T[16:30:00],
        status: "scheduled"
      )

    %{program: program, session: session}
  end

  # The whole page is driven from the URL so a view survives a refresh and the
  # browser's back button steps periods.
  describe "the URL is the source of truth" do
    test "defaults to the month grid around today", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/schedule")
      render_async(view)

      assert has_element?(view, "#schedule-grid")
      assert has_element?(view, "#view-mode-month[aria-pressed='true']")
    end

    for mode <- ~w(day week month) do
      test "#{mode} renders when the URL asks for it", %{conn: conn} do
        {:ok, view, _html} = live(conn, ~p"/provider/schedule?view=#{unquote(mode)}&date=2026-08-19")
        render_async(view)

        assert has_element?(view, "#view-mode-#{unquote(mode)}[aria-pressed='true']")
      end
    end

    # An unknown view or an unparseable date is a hand-edited URL, not a crash.
    test "falls back rather than failing on a nonsense URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/schedule?view=decade&date=not-a-date")
      render_async(view)

      assert has_element?(view, "#view-mode-month[aria-pressed='true']")
      assert has_element?(view, "#schedule-grid")
    end
  end

  describe "moving through time" do
    test "stepping back a month and forward again returns to the start", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/schedule?view=month&date=2026-08-19")
      render_async(view)

      view |> element("#schedule-prev") |> render_click()
      assert_patched(view, ~p"/provider/schedule?view=month&date=2026-07-19")

      view |> element("#schedule-next") |> render_click()
      assert_patched(view, ~p"/provider/schedule?view=month&date=2026-08-19")
    end

    test "today jumps back to now", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/schedule?view=day&date=2020-01-01")
      render_async(view)

      view |> element("#schedule-today") |> render_click()

      assert_patched(view, ~p"/provider/schedule?view=day&date=#{Date.to_iso8601(Date.utc_today())}")
    end

    # Stepping alone would make a distant date a long click-through, and the
    # retired list had a date picker.
    test "jumping to a date patches straight there", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/schedule?view=month&date=2026-08-19")
      render_async(view)

      view
      |> element("#schedule-date-form")
      |> render_change(%{"date" => "2027-03-04"})

      assert_patched(view, ~p"/provider/schedule?view=month&date=2027-03-04")
    end

    test "switching view keeps the date you were looking at", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/schedule?view=month&date=2026-08-19")
      render_async(view)

      view |> element("#view-mode-week") |> render_click()

      assert_patched(view, ~p"/provider/schedule?view=week&date=2026-08-19")
    end
  end

  describe "sessions on the grid" do
    test "a session shows on its day and links to the roster", %{conn: conn, session: session} do
      {:ok, view, _html} = live(conn, ~p"/provider/schedule?view=month&date=2026-08-19")
      render_async(view)

      assert has_element?(view, "#schedule-session-#{session.id}")

      assert view
             |> element("#schedule-session-#{session.id}")
             |> render() =~ "/provider/participation/#{session.id}"
    end

    test "a session outside the viewed period is not rendered", %{conn: conn, session: session} do
      {:ok, view, _html} = live(conn, ~p"/provider/schedule?view=month&date=2026-11-19")
      render_async(view)

      refute has_element?(view, "#schedule-session-#{session.id}")
    end

    # A month grid pads to whole weeks, so late July is on screen in the August
    # view. The query must cover the padding or those cells would be drawn empty
    # while sessions sit on them.
    test "a session in the padded week of an adjacent month still renders", %{conn: conn, program: program} do
      padded = insert(:program_session_schema, program_id: program.id, session_date: ~D[2026-07-28])

      {:ok, view, _html} = live(conn, ~p"/provider/schedule?view=month&date=2026-08-19")
      render_async(view)

      assert has_element?(view, "#schedule-session-#{padded.id}")
    end

    # The two fields the calendar adds to the query. `ProgramSession.occupancy/2`
    # matches on :max_capacity and raises on a row without it, so a summary that
    # lost the key would take the page down rather than degrade.
    test "an oversubscribed session is marked, and the day view shows where it is", %{
      conn: conn,
      program: program
    } do
      full =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: ~D[2026-08-20],
          location: "Gym B",
          max_capacity: 1
        )

      for _ <- 1..2, do: insert(:participation_record_schema, session_id: full.id, status: :registered)

      {:ok, view, _html} = live(conn, ~p"/provider/schedule?view=month&date=2026-08-19")
      render_async(view)

      assert has_element?(view, "[data-occupancy='over']")

      {:ok, day, _html} = live(conn, ~p"/provider/schedule?view=day&date=2026-08-20")
      render_async(day)

      assert render(day) =~ "Gym B"
    end

    test "another provider's session never appears", %{conn: conn} do
      foreign_program = insert(:program_schema, provider_id: insert(:provider_profile_schema).id)
      foreign = insert(:program_session_schema, program_id: foreign_program.id, session_date: ~D[2026-08-19])

      {:ok, view, _html} = live(conn, ~p"/provider/schedule?view=month&date=2026-08-19")
      render_async(view)

      refute has_element?(view, "#schedule-session-#{foreign.id}")
    end
  end

  describe "navigation chrome" do
    test "marks Schedule as the active sidebar item", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/schedule")
      render_async(view)

      assert has_element?(view, "[aria-current='page']")
    end
  end
end
