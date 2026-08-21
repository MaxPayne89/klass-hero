defmodule KlassHeroWeb.Staff.StaffDashboardLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.Factory, only: [insert: 2]
  import KlassHero.ProviderFixtures

  alias KlassHero.Accounts.User
  alias KlassHero.Provider.PayRate

  # A program on this staff member's dashboard: the write row the assignment's FK
  # needs, the listing row the dashboard renders, and the Program Staff Assignment
  # that puts it there. Category is arbitrary — since #1323 it gates nothing, so
  # these tests no longer derive it from `staff.tags`.
  defp assigned_listing(provider, staff, attrs \\ []) do
    category = Keyword.get(attrs, :category, "sports")

    # `end_date` goes on the **write** row as well as the listing: closure is read
    # from `programs`, never from the projection, so setting it only on the
    # listing would leave the program open however long ago it ended (#1082).
    write =
      insert(:program_schema,
        provider_id: provider.id,
        category: category,
        end_date: Keyword.get(attrs, :end_date)
      )

    # `title:` is copied from the write row rather than left to the factory
    # sequence: the projection keeps the two in step in production, and since
    # #1082 the dashboard reads the write row, so a fixture that let them drift
    # would be testing a state that cannot occur.
    listing =
      insert(
        :program_listing_schema,
        Keyword.merge(
          [id: write.id, provider_id: provider.id, category: category, title: write.title],
          attrs
        )
      )

    program_assignment_fixture(%{
      provider_id: provider.id,
      program_id: write.id,
      staff_member_id: staff.id
    })

    listing
  end

  describe "staff dashboard" do
    setup %{conn: conn} do
      user = user_fixture(intended_roles: [:staff])
      provider = provider_profile_fixture()

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          user_id: user.id,
          active: true,
          invitation_status: :accepted,
          tags: ["sports"]
        })

      conn = log_in_user(conn, user)
      %{conn: conn, user: user, provider: provider, staff: staff}
    end

    test "renders staff dashboard with business name", %{conn: conn, provider: provider} do
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      assert has_element?(view, "#staff-dashboard")
      assert has_element?(view, "#business-name")
      assert render(view) =~ provider.business_name
    end

    test "shows assigned programs section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      assert has_element?(view, "#assigned-programs")
    end

    test "shows welcome message with staff first name", %{conn: conn, staff: staff} do
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      assert render(view) =~ staff.first_name
    end

    test "shows the staff member's own hourly pay rate when set", %{conn: conn, staff: staff} do
      {:ok, pay_rate} = PayRate.hourly(Decimal.new("25.00"))

      {:ok, _updated} =
        KlassHero.Provider.update_staff_member(staff.provider_id, staff.id, %{pay_rate: pay_rate})

      {:ok, _view, html} = live(conn, ~p"/staff/dashboard")

      assert html =~ "€25.00 / hour"
    end

    test "hides pay rate section when no rate is set", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/staff/dashboard")

      refute html =~ "rate-label"
      refute html =~ "/ hour"
      refute html =~ "/ session"
    end

    test "a Closed Program is listed read-only, with no way to act on it (#1082)", %{
      conn: conn,
      provider: provider,
      staff: staff
    } do
      closed = assigned_listing(provider, staff, end_date: Date.add(Date.utc_today(), -20))

      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      assert has_element?(view, "#completed-programs")
      refute has_element?(view, "#sessions-link-#{closed.id}")
      refute has_element?(view, "#roster-btn-#{closed.id}")
    end

    test "a Closed Program's roster refuses a forged event, not only a hidden button", %{
      conn: conn,
      provider: provider,
      staff: staff
    } do
      closed = assigned_listing(provider, staff, end_date: Date.add(Date.utc_today(), -20))

      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      render_click(view, "view_roster", %{"id" => closed.id, "title" => closed.title})

      refute has_element?(view, "#staff-roster-modal")
    end

    test "a program inside its grace window stays actionable", %{
      conn: conn,
      provider: provider,
      staff: staff
    } do
      recent = assigned_listing(provider, staff, end_date: Date.add(Date.utc_today(), -2))

      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      assert has_element?(view, "#roster-btn-#{recent.id}")
      refute has_element?(view, "#completed-programs")
    end

    test "the Completed section is absent when nothing has closed", %{
      conn: conn,
      provider: provider,
      staff: staff
    } do
      assigned_listing(provider, staff)

      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      refute has_element?(view, "#completed-programs")
    end

    test "non-staff user is redirected", %{} do
      non_staff_user = user_fixture()
      non_staff_conn = build_conn() |> log_in_user(non_staff_user)

      assert {:error, {:redirect, %{to: "/"}}} = live(non_staff_conn, ~p"/staff/dashboard")
    end

    test "unauthenticated user is redirected", %{} do
      assert {:error, {:redirect, _}} = live(build_conn(), ~p"/staff/dashboard")
    end

    test "program cards show Sessions and Roster action buttons", %{
      conn: conn,
      provider: provider,
      staff: staff
    } do
      program = assigned_listing(provider, staff)

      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      assert has_element?(view, "#sessions-link-#{program.id}")
      assert has_element?(view, "#roster-btn-#{program.id}")
    end

    test "clicking Roster opens roster modal with enrolled children", %{
      conn: conn,
      provider: provider,
      staff: staff
    } do
      program = assigned_listing(provider, staff)

      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      refute has_element?(view, "#staff-roster-modal")

      view |> element("#roster-btn-#{program.id}") |> render_click()

      assert has_element?(view, "#staff-roster-modal")
      assert has_element?(view, "#staff-roster-modal", program.title)
    end

    test "closing roster modal hides it", %{conn: conn, provider: provider, staff: staff} do
      program = assigned_listing(provider, staff)

      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      view |> element("#roster-btn-#{program.id}") |> render_click()
      assert has_element?(view, "#staff-roster-modal")

      view |> element("#close-roster-btn") |> render_click()
      refute has_element?(view, "#staff-roster-modal")
    end

    test "roster button rejects program not in assigned set", %{
      conn: conn,
      provider: _provider
    } do
      other_program_id = Ecto.UUID.generate()

      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      view
      |> render_hook("view_roster", %{"id" => other_program_id})

      assert render(view) =~ "Unauthorized"
    end
  end

  describe "staff roster messaging controls" do
    setup %{conn: conn} do
      parent_user = user_fixture(intended_roles: [:parent])

      provider =
        provider_profile_fixture()

      user = user_fixture(intended_roles: [:staff])

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          user_id: user.id,
          active: true,
          invitation_status: :accepted,
          tags: ["sports"]
        })

      # Write model (programs table) — needed for enrollment FK
      program_write =
        insert(:program_schema,
          provider_id: provider.id,
          category: "sports"
        )

      # Read model (program_listings table) — needed for dashboard display
      program =
        insert(:program_listing_schema,
          id: program_write.id,
          provider_id: provider.id,
          category: "sports"
        )

      program_assignment_fixture(%{
        provider_id: provider.id,
        program_id: program_write.id,
        staff_member_id: staff.id
      })

      parent_profile = insert(:parent_profile_schema, identity_id: parent_user.id)

      {child, _parent} = KlassHero.Factory.insert_child_with_guardian(parent: parent_profile)

      enrollment =
        insert(:enrollment_schema,
          program_id: program.id,
          child_id: child.id,
          parent_id: parent_profile.id,
          status: "confirmed",
          confirmed_at: DateTime.utc_now()
        )

      conn = log_in_user(conn, user)

      %{
        conn: conn,
        user: user,
        parent_user: parent_user,
        provider: provider,
        staff: staff,
        program: program,
        enrollment: enrollment
      }
    end

    test "roster modal shows enabled message button for confirmed enrollment", %{
      conn: conn,
      program: program,
      enrollment: enrollment
    } do
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      view |> element("#roster-btn-#{program.id}") |> render_click()

      assert has_element?(view, "#staff-roster-modal")
      assert has_element?(view, "#staff-msg-#{enrollment.id}")
      refute has_element?(view, "#staff-msg-#{enrollment.id}[disabled]")
    end

    test "roster modal shows broadcast link when entitled and enrollments exist", %{
      conn: conn,
      program: program
    } do
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      view |> element("#roster-btn-#{program.id}") |> render_click()

      assert has_element?(view, "#staff-broadcast-#{program.id}")
      # Should be a link, not a disabled button
      assert has_element?(view, "a#staff-broadcast-#{program.id}")
    end

    test "send_message_to_parent creates conversation and navigates to staff messages", %{
      conn: conn,
      program: program,
      parent_user: parent_user
    } do
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      view |> element("#roster-btn-#{program.id}") |> render_click()

      view
      |> render_hook("send_message_to_parent", %{"parent-user-id" => parent_user.id})

      {path, _flash} = assert_redirect(view)
      assert path =~ "/staff/messages/"
    end

    test "send_message_to_parent rejects tampered parent_user_id", %{
      conn: conn,
      program: program
    } do
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      view |> element("#roster-btn-#{program.id}") |> render_click()

      view
      |> render_hook("send_message_to_parent", %{"parent-user-id" => Ecto.UUID.generate()})

      assert render(view) =~ "Cannot message this parent"
    end
  end

  describe "staff roster messaging controls (former starter-tier provider)" do
    setup %{conn: conn} do
      provider = provider_profile_fixture()
      user = user_fixture(intended_roles: [:staff])

      staff =
        staff_member_fixture(%{
          provider_id: provider.id,
          user_id: user.id,
          active: true,
          invitation_status: :accepted,
          tags: ["sports"]
        })

      program_write =
        insert(:program_schema, provider_id: provider.id, category: "sports")

      program =
        insert(:program_listing_schema,
          id: program_write.id,
          provider_id: provider.id,
          category: "sports"
        )

      program_assignment_fixture(%{
        provider_id: provider.id,
        program_id: program_write.id,
        staff_member_id: staff.id
      })

      {child, parent} = KlassHero.Factory.insert_child_with_guardian()

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "confirmed",
        confirmed_at: DateTime.utc_now()
      )

      conn = log_in_user(conn, user)
      %{conn: conn, provider: provider, staff: staff, program: program}
    end

    test "roster modal shows broadcast link for staff of former starter-tier provider", %{
      conn: conn,
      program: program
    } do
      # Provider tiers removed (ADR-0004): staff inherit messaging from any provider
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      view |> element("#roster-btn-#{program.id}") |> render_click()

      assert has_element?(view, "#staff-roster-modal")
      # Broadcast is a navigable link, not a disabled button
      assert has_element?(view, "a#staff-broadcast-#{program.id}")
      refute has_element?(view, "button#staff-broadcast-#{program.id}[disabled]")
    end
  end

  describe "cross-navigation for dual-role users" do
    setup %{conn: conn} do
      %{user: user} = fixtures = KlassHero.ProviderFixtures.dual_role_user_fixture()
      Map.put(fixtures, :conn, log_in_user(conn, user))
    end

    test "shows link to provider dashboard for dual-role users", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")
      assert has_element?(view, "#cross-nav-provider-link")
    end
  end

  # Shared wiring: a staff-only user (no provider profile of their own),
  # employed at someone else's business, logged in.
  defp staff_only_setup(%{conn: conn}) do
    user = user_fixture(intended_roles: [:staff])
    provider = provider_profile_fixture()

    staff =
      staff_member_fixture(%{
        provider_id: provider.id,
        user_id: user.id,
        active: true,
        invitation_status: :accepted
      })

    %{conn: log_in_user(conn, user), user: user, provider: provider, staff: staff}
  end

  describe "cross-navigation for staff-only users" do
    setup :staff_only_setup

    test "does NOT show link to provider dashboard for staff-only users", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")
      refute has_element?(view, "#cross-nav-provider-link")
    end
  end

  describe "become a provider CTA (#968)" do
    setup :staff_only_setup

    test "staff-only user sees the CTA", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      assert has_element?(view, "#become-provider-cta")
      assert has_element?(view, "#become-provider-cta-button")
    end

    test "user with their own provider profile sees no CTA", %{conn: conn, user: user} do
      provider_profile_fixture(identity_id: user.id)

      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      refute has_element?(view, "#become-provider-cta")
    end

    test "clicking the CTA reveals the confirm step", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      refute has_element?(view, "#become-provider-confirm")

      view |> element("#become-provider-cta-button") |> render_click()

      assert has_element?(view, "#become-provider-confirm")
      assert has_element?(view, "#become-provider-confirm-button")
      assert has_element?(view, "#become-provider-cancel-button")
    end

    test "cancelling the confirm step returns to the CTA", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      view |> element("#become-provider-cta-button") |> render_click()
      view |> element("#become-provider-cancel-button") |> render_click()

      refute has_element?(view, "#become-provider-confirm")
      assert has_element?(view, "#become-provider-cta-button")
    end

    test "confirming creates the draft profile, grants :provider, and navigates to profile completion",
         %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      view |> element("#become-provider-cta-button") |> render_click()
      view |> element("#become-provider-confirm-button") |> render_click()

      assert_redirect(view, ~p"/provider/complete-profile")

      # Both writes completed synchronously before the redirect.
      assert {:ok, profile} = KlassHero.Provider.get_provider_by_identity(user.id)
      assert profile.profile_status == :draft

      reloaded = KlassHero.Repo.get!(User, user.id)
      assert :provider in reloaded.intended_roles
      assert :staff in reloaded.intended_roles
    end

    test "a crafted confirm event from an existing provider creates no second profile", %{
      conn: conn,
      user: user
    } do
      existing = provider_profile_fixture(identity_id: user.id)

      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")

      # No CTA rendered, but a client can still push the event.
      render_click(view, "confirm_provider_upgrade", %{})

      assert {:ok, profile} = KlassHero.Provider.get_provider_by_identity(user.id)
      assert profile.id == existing.id
      refute :provider in KlassHero.Repo.get!(User, user.id).intended_roles
    end

    test "stale tab: confirming after upgrading elsewhere re-converges the whole page", %{
      conn: conn,
      user: user
    } do
      # Mount while still staff-only — CTA visible, no cross-nav link.
      {:ok, view, _html} = live(conn, ~p"/staff/dashboard")
      assert has_element?(view, "#become-provider-cta")
      refute has_element?(view, "#cross-nav-provider-link")

      # The upgrade happens in another tab.
      provider_profile_fixture(identity_id: user.id)

      view |> element("#become-provider-cta-button") |> render_click()
      view |> element("#become-provider-confirm-button") |> render_click()

      # The page converges to provider truth: CTA gone AND the provider
      # dashboard link appears — not one without the other.
      refute has_element?(view, "#become-provider-cta")
      assert has_element?(view, "#cross-nav-provider-link")
    end
  end
end
