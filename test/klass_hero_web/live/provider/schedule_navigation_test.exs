defmodule KlassHeroWeb.Provider.ScheduleNavigationTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_provider

  describe "schedule tab in dashboard navigation" do
    # Scope selectors to the in-page nav tab (the only one with
    # `data-phx-link="redirect"` and the border-b-2 underline). Phase 3 of
    # the design-handoff migration added the same /provider/schedule link
    # in the sidebar (desktop) and bottom-tab (mobile), so selecting by
    # href + text alone matches three elements now.
    test "dashboard has schedule tab linking to /provider/schedule", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      assert has_element?(
               view,
               ~s(a[href="/provider/schedule"][data-phx-link="redirect"]),
               "Schedule"
             )
    end

    test "clicking schedule tab navigates to the calendar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      view
      |> element(~s(a[href="/provider/schedule"][data-phx-link="redirect"]), "Schedule")
      |> render_click()

      assert_redirect(view, ~p"/provider/schedule")
    end
  end
end
