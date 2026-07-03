defmodule KlassHeroWeb.Admin.StaffLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  alias KlassHero.Provider.StaffMember

  describe "admin access control" do
    setup :register_and_log_in_admin

    test "admin can access /admin/staff", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/staff")
      assert html =~ "Staff Members"
    end

    test "new staff button is not shown on index", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/staff")
      refute has_element?(view, "a", "New")
    end
  end

  describe "non-admin access control" do
    setup :register_and_log_in_user

    test "non-admin is redirected from /admin/staff", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/staff")
      assert flash["error"] =~ "access"
    end
  end

  describe "unauthenticated access control" do
    test "unauthenticated user is redirected from /admin/staff", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/staff")
    end
  end

  describe "staff member list" do
    setup :register_and_log_in_admin

    test "displays staff members in the table", %{conn: conn} do
      provider = provider_profile_fixture(business_name: "Sunny Academy")

      _staff =
        staff_member_fixture(provider_id: provider.id, first_name: "Alice", last_name: "Smith")

      {:ok, view, _html} = live(conn, ~p"/admin/staff")

      assert has_element?(view, "td", "Alice")
      assert has_element?(view, "td", "Smith")
    end

    test "displays provider business name", %{conn: conn} do
      provider = provider_profile_fixture(business_name: "Sunny Academy")
      _staff = staff_member_fixture(provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/admin/staff")

      assert has_element?(view, "td", "Sunny Academy")
    end
  end

  describe "edit staff member" do
    setup :register_and_log_in_admin

    test "admin can toggle active status to false", %{conn: conn} do
      provider = provider_profile_fixture()

      staff =
        staff_member_fixture(provider_id: provider.id, first_name: "Bob", last_name: "Jones")

      {:ok, view, _html} = live(conn, ~p"/admin/staff/#{staff.id}/edit")

      view
      |> form("#resource-form", %{change: %{active: false}})
      |> render_submit(%{"save-type" => "save"})

      schema =
        KlassHero.Repo.get!(
          StaffMember,
          staff.id
        )

      assert schema.active == false
    end

    test "admin cannot edit provider-owned fields", %{conn: conn} do
      provider = provider_profile_fixture()

      staff =
        staff_member_fixture(
          provider_id: provider.id,
          first_name: "Original",
          last_name: "Name",
          role: "Instructor"
        )

      {:ok, view, _html} = live(conn, ~p"/admin/staff/#{staff.id}/edit")

      # Trigger: admin submits the edit form with only the active toggle changed
      # Why: admin_changeset only casts :active; readonly fields (first_name, role)
      #      are not rendered as editable inputs, so they can't be submitted at all
      # Outcome: first_name, role remain unchanged in the database
      view
      |> form("#resource-form", %{
        change: %{active: false}
      })
      |> render_submit(%{"save-type" => "save"})

      schema =
        KlassHero.Repo.get!(
          StaffMember,
          staff.id
        )

      assert schema.first_name == "Original"
      assert schema.role == "Instructor"
      assert schema.active == false
    end
  end
end
