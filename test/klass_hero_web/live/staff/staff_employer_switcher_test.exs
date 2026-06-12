defmodule KlassHeroWeb.Staff.StaffEmployerSwitcherTest do
  @moduledoc """
  Employer switcher on the staff dashboard (#969 staff-context switcher).

  A user can hold active staff rows at several providers; the scope carries
  the "currently selected employment". The picker lets them switch, and the
  selection is remembered (DB-persisted) across mounts.
  """

  use KlassHeroWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]
  import KlassHero.AccountsFixtures
  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  # Backdates inserted_at one day apart per membership (timestamps are
  # second-precision — same-test inserts would tie) so the LAST listed
  # business is deterministically the scope default (newest employer row).
  defp log_in_staff_at(conn, business_names) do
    user = user_fixture(intended_roles: [:staff])

    providers =
      for {name, index} <- Enum.with_index(business_names) do
        provider = provider_profile_fixture(%{business_name: name})

        staff_member_fixture(%{
          provider_id: provider.id,
          user_id: user.id,
          active: true,
          invitation_status: :accepted,
          inserted_at: DateTime.add(~U[2026-01-01 10:00:00Z], index, :day)
        })

        provider
      end

    %{conn: log_in_user(conn, user), user: user, providers: providers}
  end

  describe "picker visibility" do
    test "a single-employer staff member sees no picker", %{conn: conn} do
      %{conn: conn} = log_in_staff_at(conn, ["Only Employer"])

      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      refute has_element?(view, "#employer-picker")
    end

    test "a multi-employer staff member sees all business names in the picker", %{conn: conn} do
      %{conn: conn, providers: [a, b]} = log_in_staff_at(conn, ["Alpha Sports", "Beta Camps"])

      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      assert has_element?(view, "#employer-picker")
      assert has_element?(view, "#employer-option-#{a.id}", "Alpha Sports")
      assert has_element?(view, "#employer-option-#{b.id}", "Beta Camps")
    end
  end

  describe "switching" do
    test "switching employers re-mounts the dashboard on the other business and is remembered",
         %{conn: conn} do
      %{conn: conn, providers: [a, _b]} = log_in_staff_at(conn, ["Alpha Sports", "Beta Camps"])

      # Beta's row is newer (backdated fixtures), so Beta is the scope default —
      # switching to ALPHA exercises actual persistence, not the default.
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")
      assert has_element?(view, "#business-name h1", "Beta Camps")

      view |> element("#employer-option-#{a.id}") |> render_click()
      assert_redirect(view, "/staff/dashboard")

      # Fresh mount resolves the scope to the remembered selection.
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")
      assert has_element?(view, "#business-name h1", "Alpha Sports")
    end

    test "switching to a business that deactivated the row mid-session re-converges fully",
         %{conn: conn} do
      %{conn: conn, user: user, providers: [_a, b]} =
        log_in_staff_at(conn, ["Alpha Sports", "Beta Camps"])

      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      # The Beta row is deactivated from elsewhere while the picker is open.
      {1, _} =
        KlassHero.Repo.update_all(
          from(s in "staff_members",
            where:
              s.provider_id == type(^b.id, :binary_id) and
                s.user_id == type(^user.id, :binary_id)
          ),
          set: [active: false]
        )

      # Full re-mount re-resolves the scope: dead option gone, picker hidden
      # (one membership left), dashboard on the surviving employer.
      view |> element("#employer-option-#{b.id}") |> render_click()
      flash = assert_redirect(view, "/staff/dashboard")
      assert flash["error"] =~ "no longer on that team"

      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")
      refute has_element?(view, "#employer-picker")
      assert has_element?(view, "#business-name h1", "Alpha Sports")
    end

    test "a tampered non-UUID provider id is handled like not-staffed, no crash", %{conn: conn} do
      %{conn: conn} = log_in_staff_at(conn, ["Alpha Sports", "Beta Camps"])

      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      render_click(view, "switch_employer", %{"provider-id" => "not-a-uuid"})
      flash = assert_redirect(view, "/staff/dashboard")
      assert flash["error"] =~ "no longer on that team"
    end
  end

  describe "employer-first default (#969 finding 1 regression)" do
    test "a founder self-staffed at their own business still defaults to the employer", %{
      conn: conn
    } do
      user = user_fixture(intended_roles: [:staff, :provider])
      employer = provider_profile_fixture(%{business_name: "Employer GmbH"})

      own_business =
        provider_profile_fixture(%{identity_id: user.id, business_name: "Own Thing"})

      # Employer row first, self row second (newer) — newest-wins would flip
      # the dashboard to "Own Thing"; employer-first keeps it on the employer.
      staff_member_fixture(%{
        provider_id: employer.id,
        user_id: user.id,
        active: true,
        invitation_status: :accepted
      })

      staff_member_fixture(%{
        provider_id: own_business.id,
        user_id: user.id,
        active: true,
        invitation_status: :accepted
      })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      assert has_element?(view, "#business-name h1", "Employer GmbH")
      assert has_element?(view, "#employer-picker")
    end
  end
end
