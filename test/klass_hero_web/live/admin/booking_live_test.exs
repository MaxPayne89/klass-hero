defmodule KlassHeroWeb.Admin.BookingLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.ProgramCatalog.Program
  alias KlassHeroWeb.Admin.BookingLive

  describe "admin access control" do
    setup :register_and_log_in_admin

    test "admin can access /admin/bookings", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/bookings")
      assert html =~ "Bookings"
    end

    test "new booking button is not shown on index", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/bookings")
      refute has_element?(view, "a", "New")
    end
  end

  describe "non-admin access control" do
    setup :register_and_log_in_user

    test "non-admin is redirected from /admin/bookings", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/bookings")
      assert flash["error"] =~ "access"
    end
  end

  describe "unauthenticated access control" do
    test "unauthenticated user is redirected from /admin/bookings", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/bookings")
    end
  end

  describe "booking list" do
    setup :register_and_log_in_admin

    test "displays bookings in the table", %{conn: conn} do
      enrollment = insert(:enrollment_schema, status: "pending")

      program =
        KlassHero.Repo.get!(
          Program,
          enrollment.program_id
        )

      {:ok, view, _html} = live(conn, ~p"/admin/bookings")

      assert has_element?(view, "td", program.title)
      assert has_element?(view, "td", "Pending")
    end
  end

  describe "booking show" do
    setup :register_and_log_in_admin

    test "displays booking detail", %{conn: conn} do
      enrollment =
        insert(:enrollment_schema, status: "confirmed", special_requirements: "Allergic to nuts")

      {:ok, _view, html} = live(conn, ~p"/admin/bookings/#{enrollment.id}/show")

      assert html =~ "Confirmed"
      assert html =~ "Allergic to nuts"
    end
  end

  describe "can?/3 cancel_booking visibility" do
    @cancel_cases [
      {:pending, true},
      {:confirmed, true},
      {:completed, false},
      {:cancelled, false}
    ]

    test "is permitted only for pending and confirmed statuses" do
      for {status, expected} <- @cancel_cases do
        assert BookingLive.can?(%{}, :cancel_booking, %{status: status}) == expected,
               "can?(:cancel_booking, status: #{inspect(status)}) should be #{expected}"
      end
    end
  end

  describe "can?/3 fixed-action gates" do
    @fixed_cases [
      {:new, false},
      {:edit, false},
      {:delete, false},
      {:index, true},
      {:show, true}
    ]

    test "denies new/edit/delete and permits index/show" do
      for {action, expected} <- @fixed_cases do
        assert BookingLive.can?(%{}, action, %{}) == expected,
               "can?(#{inspect(action)}) should be #{expected}"
      end
    end

    test "denies unknown actions regardless of status" do
      refute BookingLive.can?(%{}, :unknown_action, %{status: :pending})
    end
  end
end
