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

  defp log_in_staff_at(conn, business_names) do
    user = user_fixture(intended_roles: [:staff])

    providers =
      for name <- business_names do
        provider = provider_profile_fixture(%{business_name: name})

        staff_member_fixture(%{
          provider_id: provider.id,
          user_id: user.id,
          active: true,
          invitation_status: :accepted
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
      %{conn: conn, providers: [_a, b]} = log_in_staff_at(conn, ["Alpha Sports", "Beta Camps"])

      {:ok, view, html} = live(conn, ~p"/staff/dashboard")

      # Default: oldest employer row was created first → Alpha is newest...
      # selection ordering makes this deterministic, asserted further below.
      assert html =~ "Welcome"

      view |> element("#employer-option-#{b.id}") |> render_click()
      assert_redirect(view, "/staff/dashboard")

      # Fresh mount resolves the scope to the remembered selection.
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")
      assert has_element?(view, "#business-name h1", "Beta Camps")
    end

    test "switching to a business that deactivated the row mid-session shows an error and stays",
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

      view |> element("#employer-option-#{b.id}") |> render_click()

      assert has_element?(view, "#staff-dashboard")
      assert render(view) =~ "no longer on that team"
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
