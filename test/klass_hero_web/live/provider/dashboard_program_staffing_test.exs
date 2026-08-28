defmodule KlassHeroWeb.Provider.DashboardProgramStaffingTest do
  @moduledoc """
  The per-program staffing panel on the Programs tab: who is on a program, who
  leads it, and the add/promote/remove controls.

  Sibling of `dashboard_team_test.exs`, which covers the provider-wide staff
  directory at `/provider/dashboard/team`. This one is per-program.
  """
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.Provider

  setup :register_and_log_in_provider

  setup %{provider: provider} do
    program = insert_listed_program(provider, "Summer Camp")

    %{
      program: program,
      ann: insert_staff(provider, "Ann", "Blake"),
      bo: insert_staff(provider, "Bo", "Crane"),
      cy: insert_staff(provider, "Cy", "Dunn")
    }
  end

  describe "opening and closing the panel" do
    test "opens from the program row and closes again", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      refute has_element?(view, "#program-staffing-modal")

      view |> element("#manage-staffing-#{program.id}") |> render_click()
      assert has_element?(view, "#program-staffing-modal")

      view |> element("#program-staffing-modal button[phx-click=close_staffing]") |> render_click()
      refute has_element?(view, "#program-staffing-modal")
    end

    test "shows an empty state when nobody is on the program", %{conn: conn, program: program} do
      view = open_panel(conn, program)

      assert has_element?(view, "#staffing-empty")
    end

    test "lists everyone already on the program", %{conn: conn, program: program, ann: ann, bo: bo} do
      for staff <- [ann, bo], do: assign_staff!(program, staff)

      view = open_panel(conn, program)

      assert has_element?(view, "#staffing-member-#{ann.id}")
      assert has_element?(view, "#staffing-member-#{bo.id}")
    end
  end

  describe "adding staff" do
    test "puts a second staff member on the program", %{conn: conn, program: program, ann: ann, bo: bo} do
      assign_staff!(program, ann)

      view = open_panel(conn, program)
      refute has_element?(view, "#staffing-member-#{bo.id}")

      view |> form("#staffing-add-form", %{"staff-id" => bo.id}) |> render_submit()

      assert has_element?(view, "#staffing-member-#{ann.id}")
      assert has_element?(view, "#staffing-member-#{bo.id}")
      assert active_staff_ids(program) == MapSet.new([ann.id, bo.id])
    end

    test "stops offering someone once they are on the program", %{conn: conn, program: program, bo: bo} do
      view = open_panel(conn, program)

      assert has_element?(view, ~s|#staffing-add-select option[value="#{bo.id}"]|)

      view |> form("#staffing-add-form", %{"staff-id" => bo.id}) |> render_submit()

      refute has_element?(view, ~s|#staffing-add-select option[value="#{bo.id}"]|)
    end

    test "asks for a pick when the select is left blank", %{conn: conn, program: program} do
      view = open_panel(conn, program)

      html = view |> form("#staffing-add-form", %{"staff-id" => ""}) |> render_submit()

      assert html =~ "Pick a staff member to add."
      assert active_staff_ids(program) == MapSet.new()
    end
  end

  describe "removing staff" do
    test "takes a non-lead off the program", %{conn: conn, program: program, ann: ann, bo: bo} do
      for staff <- [ann, bo], do: assign_staff!(program, staff)
      promote!(program, ann)

      view = open_panel(conn, program)
      view |> element("#remove-staff-#{bo.id}") |> render_click()

      refute has_element?(view, "#staffing-member-#{bo.id}")
      assert active_staff_ids(program) == MapSet.new([ann.id])
    end

    test "refuses to remove the lead and says why", %{conn: conn, program: program, ann: ann} do
      assign_staff!(program, ann)
      promote!(program, ann)

      view = open_panel(conn, program)

      # The button is disabled in the UI; the click asserts the handler refuses
      # too, since a disabled attribute is not a security boundary.
      html = render_click(view, "remove_staff_member", %{"staff-id" => ann.id})

      assert html =~ "lead instructor"
      assert has_element?(view, "#staffing-member-#{ann.id}")
      assert active_staff_ids(program) == MapSet.new([ann.id])
    end

    test "disables the remove control on the lead's row", %{conn: conn, program: program, ann: ann, bo: bo} do
      for staff <- [ann, bo], do: assign_staff!(program, staff)
      promote!(program, ann)

      view = open_panel(conn, program)

      assert has_element?(view, "#remove-staff-#{ann.id}[disabled]")
      refute has_element?(view, "#remove-staff-#{bo.id}[disabled]")
    end
  end

  describe "promoting to lead" do
    test "moves the badge and updates the program row", %{conn: conn, program: program, ann: ann, bo: bo} do
      for staff <- [ann, bo], do: assign_staff!(program, staff)
      promote!(program, ann)

      view = open_panel(conn, program)
      assert has_element?(view, "#staffing-lead-badge-#{ann.id}")

      view |> element("#promote-staff-#{bo.id}") |> render_click()

      assert has_element?(view, "#staffing-lead-badge-#{bo.id}")
      refute has_element?(view, "#staffing-lead-badge-#{ann.id}")
      assert %{id: lead_id} = Provider.get_lead_instructor(program.id)
      assert lead_id == bo.id
    end

    test "offers no promote control on the current lead", %{conn: conn, program: program, ann: ann} do
      assign_staff!(program, ann)
      promote!(program, ann)

      view = open_panel(conn, program)

      refute has_element?(view, "#promote-staff-#{ann.id}")
    end

    test "frees the previous lead to be removed", %{conn: conn, program: program, ann: ann, bo: bo} do
      for staff <- [ann, bo], do: assign_staff!(program, staff)
      promote!(program, ann)

      view = open_panel(conn, program)
      view |> element("#promote-staff-#{bo.id}") |> render_click()
      view |> element("#remove-staff-#{ann.id}") |> render_click()

      assert active_staff_ids(program) == MapSet.new([bo.id])
    end
  end

  describe "IDOR ownership guards" do
    setup %{ann: ann} do
      victim = insert(:provider_profile_schema)
      victim_program = insert_listed_program(victim, "Not Yours")
      victim_staff = insert_staff(victim, "Eve", "Foreign")

      %{victim_program: victim_program, victim_staff: victim_staff, mine: ann}
    end

    test "manage_staffing on a foreign program opens no panel", %{conn: conn, victim_program: victim_program} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view = assert_idor_guarded(view, "manage_staffing", victim_program.id, "Program not found.")

      refute has_element?(view, "#program-staffing-modal")
    end

    test "a foreign staff member cannot be added to my program", %{
      conn: conn,
      program: program,
      victim_staff: victim_staff
    } do
      view = open_panel(conn, program)

      html = render_click(view, "assign_staff_member", %{"staff-id" => victim_staff.id})

      assert html =~ "could not be found"
      assert active_staff_ids(program) == MapSet.new()
    end

    test "a foreign staff member cannot be promoted on my program", %{
      conn: conn,
      program: program,
      victim_staff: victim_staff
    } do
      view = open_panel(conn, program)

      html = render_click(view, "promote_to_lead", %{"staff-id" => victim_staff.id})

      assert html =~ "could not be found"
      assert Provider.get_lead_instructor(program.id) == nil
    end
  end

  # The picker filters deactivated staff, so these are only reachable by a crafted
  # phx-value — or a stale panel left open in another tab across a deactivation.
  # Before #1306 they wrote a real row that then rendered nowhere.
  describe "deactivated staff" do
    setup %{provider: provider} do
      former = insert_staff(provider, "Del", "Gone")
      {:ok, _} = Provider.deactivate_staff_member(former)

      %{former: former}
    end

    test "the picker does not offer them", %{conn: conn, program: program, former: former} do
      view = open_panel(conn, program)

      refute has_element?(view, ~s(#staffing-add-form option[value="#{former.id}"]))
    end

    test "a deactivated staff member cannot be added to my program", %{
      conn: conn,
      program: program,
      former: former
    } do
      view = open_panel(conn, program)

      html = render_click(view, "assign_staff_member", %{"staff-id" => former.id})

      assert html =~ "could not be found"
      assert active_staff_ids(program) == MapSet.new()
    end

    test "a deactivated staff member cannot be promoted on my program", %{
      conn: conn,
      program: program,
      former: former
    } do
      view = open_panel(conn, program)

      html = render_click(view, "promote_to_lead", %{"staff-id" => former.id})

      assert html =~ "could not be found"
      assert Provider.get_lead_instructor(program.id) == nil
    end

    test "the panel stays usable afterwards", %{conn: conn, program: program, former: former, ann: ann} do
      view = open_panel(conn, program)

      render_click(view, "assign_staff_member", %{"staff-id" => former.id})

      assert has_element?(view, "#program-staffing-modal")

      view |> form("#staffing-add-form", %{"staff-id" => ann.id}) |> render_submit()

      assert has_element?(view, "#staffing-member-#{ann.id}")
    end
  end

  # The table column and the staff filter both read one `ProgramStaffing`
  # read-model. Before #1310 the column rendered the lead alone and the filter
  # matched on that rendered lead, so a leaderless-but-staffed program looked
  # empty and a non-lead staff member found none of their programs.
  describe "the programs table staff column" do
    test "a staffed but leaderless program shows its headcount, not Unassigned", %{
      conn: conn,
      program: program,
      ann: ann,
      bo: bo
    } do
      for staff <- [ann, bo], do: assign_staff!(program, staff)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      assert has_element?(view, "#program-staff-leaderless-#{program.id}", "2 staff")
      refute has_element?(view, "#program-staff-empty-#{program.id}")
    end

    test "a led program shows the lead plus an overflow count", %{
      conn: conn,
      program: program,
      ann: ann,
      bo: bo
    } do
      for staff <- [ann, bo], do: assign_staff!(program, staff)
      promote!(program, ann)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      assert has_element?(view, "#program-staff-lead-#{program.id}", "Ann Blake")
      assert has_element?(view, "#program-staff-lead-#{program.id}", "+1")
    end

    test "a program nobody is on still shows Unassigned", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      assert has_element?(view, "#program-staff-empty-#{program.id}")
    end

    test "adding a non-lead refreshes the row's headcount", %{
      conn: conn,
      program: program,
      ann: ann,
      bo: bo
    } do
      assign_staff!(program, ann)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      assert has_element?(view, "#program-staff-leaderless-#{program.id}", "1 staff member")

      view |> element("#manage-staffing-#{program.id}") |> render_click()
      view |> form("#staffing-add-form", %{"staff-id" => bo.id}) |> render_submit()

      assert has_element?(view, "#program-staff-leaderless-#{program.id}", "2 staff")
    end
  end

  describe "filtering the programs table by staff member" do
    test "finds the programs a NON-LEAD staff member is on", %{
      conn: conn,
      program: program,
      ann: ann,
      bo: bo
    } do
      for staff <- [ann, bo], do: assign_staff!(program, staff)
      promote!(program, ann)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      filter_by_staff(view, bo)

      assert has_element?(view, "#programs-#{program.id}")
    end

    test "hides programs a staff member is not on", %{conn: conn, program: program, ann: ann, cy: cy} do
      assign_staff!(program, ann)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      filter_by_staff(view, cy)

      refute has_element?(view, "#programs-#{program.id}")
    end

    test "drops the row when the staff member the filter is pinned to is removed", %{
      conn: conn,
      program: program,
      ann: ann,
      bo: bo
    } do
      for staff <- [ann, bo], do: assign_staff!(program, staff)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      filter_by_staff(view, bo)
      assert has_element?(view, "#programs-#{program.id}")

      view |> element("#manage-staffing-#{program.id}") |> render_click()
      view |> element("#remove-staff-#{bo.id}") |> render_click()

      refute has_element?(view, "#programs-#{program.id}")
    end
  end

  # Drives the wrapping <form>, not the bare <select>: LiveView rejects a
  # phx-change on an input outside a form in the browser, and `element/2` +
  # render_change/2 would happily bypass that check and pass on markup no user
  # could actually trigger.
  defp filter_by_staff(view, staff) do
    view
    |> form("#programs-staff-filter-form", %{"staff_filter" => staff.id})
    |> render_change()
  end

  defp open_panel(conn, program) do
    {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
    view |> element("#manage-staffing-#{program.id}") |> render_click()
    view
  end

  # The provider programs table renders from the `program_listings` read table,
  # so a program without a matching listing row is invisible and every row-level
  # assertion below would fail for an unrelated reason.
  defp insert_listed_program(provider, title) do
    program = insert(:program_schema, provider_id: provider.id, title: title)

    program
  end

  defp insert_staff(provider, first_name, last_name) do
    insert(:staff_member_schema, provider_id: provider.id, first_name: first_name, last_name: last_name)
  end

  defp assign_staff!(program, staff) do
    {:ok, assignment} =
      Provider.assign_staff_to_program(%{
        provider_id: program.provider_id,
        program_id: program.id,
        staff_member_id: staff.id
      })

    assignment
  end

  defp promote!(program, staff) do
    {:ok, assignment} = Provider.set_lead_instructor(program.id, staff.id, program.provider_id)
    assignment
  end

  defp active_staff_ids(program) do
    program.id
    |> Provider.list_active_staff_for_program()
    |> MapSet.new(& &1.id)
  end
end
