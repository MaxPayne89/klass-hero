defmodule KlassHeroWeb.Admin.StaffLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  alias KlassHero.Provider.StaffMember
  alias KlassHero.Repo
  alias KlassHeroWeb.Admin.Actions.ActivateStaffAction
  alias KlassHeroWeb.Admin.Actions.DeactivateStaffAction
  alias KlassHeroWeb.Admin.StaffLive
  alias Phoenix.LiveView.Socket

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

  describe "can?/3 employment-action gating" do
    # Deactivate and Activate are opposite-gated on the same row, so Backpex renders
    # exactly one of them per staff member. Tested as plain functions, matching
    # BookingLive's cancel_booking gates — no item-action modal is driven anywhere
    # in this suite.
    @employment_cases [
      {:deactivate_staff, true, true},
      {:deactivate_staff, false, false},
      {:activate_staff, true, false},
      {:activate_staff, false, true}
    ]

    test "offers deactivate only for active staff and activate only for inactive" do
      for {action, active?, expected} <- @employment_cases do
        assert StaffLive.can?(%{}, action, %{active: active?}) == expected,
               "can?(#{inspect(action)}, active: #{active?}) should be #{expected}"
      end
    end

    @fixed_cases [{:new, false}, {:delete, false}, {:edit, false}, {:index, true}, {:show, true}]

    test "denies create, delete and edit; permits index and show" do
      # :edit is denied since #1237 — `active` was the only editable field, and it
      # now moves through the domain command, so the form has nothing left to write.
      for {action, expected} <- @fixed_cases do
        assert StaffLive.can?(%{}, action, %{}) == expected,
               "can?(#{inspect(action)}) should be #{expected}"
      end
    end

    test "denies unknown actions" do
      refute StaffLive.can?(%{}, :unknown_action, %{active: true})
    end
  end

  describe "employment item actions" do
    setup :register_and_log_in_admin

    test "deactivating ends the employment link through the domain command" do
      provider = provider_profile_fixture()
      staff = staff_member_fixture(provider_id: provider.id, first_name: "Bob", last_name: "Jones")

      assert {:ok, _socket} = DeactivateStaffAction.handle(bare_socket(), [staff], %{})

      reloaded = Repo.get!(StaffMember, staff.id)
      refute reloaded.active
      assert reloaded.first_name == "Bob", "the action must not touch provider-owned fields"
    end

    test "activating reinstates the employment link" do
      provider = provider_profile_fixture()
      staff = staff_member_fixture(provider_id: provider.id, active: false)

      assert {:ok, _socket} = ActivateStaffAction.handle(bare_socket(), [staff], %{})

      assert Repo.get!(StaffMember, staff.id).active
    end

    test "the edit route is no longer reachable", %{conn: conn} do
      # Backpex raises rather than redirecting when can?/3 denies a form mount, so
      # the URL cannot be used as a back door around the item actions.
      provider = provider_profile_fixture()
      staff = staff_member_fixture(provider_id: provider.id)

      assert_raise Backpex.ForbiddenError, fn -> live(conn, ~p"/admin/staff/#{staff.id}/edit") end
    end
  end

  # The actions only put a flash on the socket, so a bare one exercises handle/3
  # directly. Driving the confirm modal through LiveViewTest has no precedent in
  # this suite — BookingLive's action is tested the same way.
  defp bare_socket, do: %Socket{assigns: %{flash: %{}, __changed__: %{}}}
end
