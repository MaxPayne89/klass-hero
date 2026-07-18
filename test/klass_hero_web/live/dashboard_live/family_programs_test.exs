defmodule KlassHeroWeb.DashboardLive.FamilyProgramsTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  describe "Family Programs section (empty state)" do
    setup :register_and_log_in_user

    test "shows empty state when parent has no enrollments", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      render_async(view)

      assert has_element?(view, "#family-programs")
      assert has_element?(view, "#family-programs-empty")
      assert has_element?(view, "#family-programs-empty a[href='/programs']")
    end
  end

  describe "Family Programs section (with enrollments)" do
    setup :register_and_log_in_user_with_child

    test "active enrollment renders program card", %{conn: conn, parent: parent, child: child} do
      program = insert(:program_schema, title: "Soccer Academy", end_date: ~D[2027-06-30])

      enrollment =
        insert(:enrollment_schema,
          parent_id: parent.id,
          child_id: child.id,
          program_id: program.id,
          status: "confirmed"
        )

      {:ok, view, _html} = live(conn, ~p"/dashboard")
      render_async(view)

      refute has_element?(view, "#family-programs-empty")
      assert has_element?(view, "#family_programs-#{enrollment.id}")
    end

    test "active card has contact button", %{conn: conn, parent: parent, child: child} do
      program = insert(:program_schema, end_date: ~D[2027-06-30])

      insert(:enrollment_schema,
        parent_id: parent.id,
        child_id: child.id,
        program_id: program.id,
        status: "confirmed"
      )

      {:ok, view, _html} = live(conn, ~p"/dashboard")
      render_async(view)

      assert has_element?(
               view,
               ~s|#family-programs button[phx-click="contact_provider"][phx-value-program-id="#{program.id}"]|
             )
    end

    test "expired enrollment by status renders", %{conn: conn, parent: parent, child: child} do
      program = insert(:program_schema, end_date: ~D[2027-06-30])

      enrollment =
        insert(:enrollment_schema,
          parent_id: parent.id,
          child_id: child.id,
          program_id: program.id,
          status: "completed",
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      {:ok, view, _html} = live(conn, ~p"/dashboard")
      render_async(view)

      refute has_element?(view, "#family-programs-empty")
      assert has_element?(view, "#family_programs-#{enrollment.id}")
    end

    test "expired enrollment by past end_date renders", %{
      conn: conn,
      parent: parent,
      child: child
    } do
      program = insert(:program_schema, end_date: ~D[2020-01-01])

      enrollment =
        insert(:enrollment_schema,
          parent_id: parent.id,
          child_id: child.id,
          program_id: program.id,
          status: "confirmed"
        )

      {:ok, view, _html} = live(conn, ~p"/dashboard")
      render_async(view)

      refute has_element?(view, "#family-programs-empty")
      assert has_element?(view, "#family_programs-#{enrollment.id}")
    end

    test "active programs appear before expired programs", %{
      conn: conn,
      parent: parent,
      child: child
    } do
      active_program = insert(:program_schema, title: "Active Soccer", end_date: ~D[2027-06-30])
      expired_program = insert(:program_schema, title: "Old Art", end_date: ~D[2020-01-01])

      active_enrollment =
        insert(:enrollment_schema,
          parent_id: parent.id,
          child_id: child.id,
          program_id: active_program.id,
          status: "confirmed"
        )

      expired_enrollment =
        insert(:enrollment_schema,
          parent_id: parent.id,
          child_id: child.id,
          program_id: expired_program.id,
          status: "confirmed"
        )

      {:ok, view, _html} = live(conn, ~p"/dashboard")
      html = render_async(view)

      active_pos = :binary.match(html, "family_programs-#{active_enrollment.id}") |> elem(0)
      expired_pos = :binary.match(html, "family_programs-#{expired_enrollment.id}") |> elem(0)

      assert active_pos < expired_pos,
             "Active program card should appear before expired program card"
    end
  end
end
