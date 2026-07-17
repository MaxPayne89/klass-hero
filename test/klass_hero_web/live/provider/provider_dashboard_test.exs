defmodule KlassHeroWeb.Provider.ProviderDashboardTest do
  @moduledoc """
  Cross-tab integration tests for the provider dashboard, which is served by four
  route-level sub-LiveViews (OverviewLive, TeamLive, ProgramsLive, EditProfileLive)
  since #904. Exercises each tab's route plus tab-to-tab navigation. Per-tab unit
  tests live in the dedicated `dashboard_team_test.exs`,
  `dashboard_self_staff_test.exs`, `dashboard_program_creation_test.exs`, and
  `edit_profile_live_test.exs` files.
  """
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.EventTestHelper
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias KlassHero.ProgramCatalog.ProgramListing
  alias KlassHero.Provider.Adapters.Driven.Projections.ProviderSessionDetails
  alias KlassHero.ProviderFixtures
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.DomainEvent

  setup :register_and_log_in_provider

  # Trigger: dashboard reads programs from program_listings (CQRS read model)
  # Why: write-side program_schema alone won't appear in the programs tab
  # Outcome: inserts into both programs (for FK constraints) and program_listings (for display)
  defp insert_program_with_listing(attrs) do
    program = KlassHero.Factory.insert(:program_schema, attrs)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %ProgramListing{}
    |> Ecto.Changeset.change(%{
      id: program.id,
      title: program.title,
      description: program.description,
      category: program.category,
      age_range: program.age_range,
      price: program.price,
      pricing_period: program.pricing_period,
      location: program.location,
      cover_image_url: program.cover_image_url,
      start_date: program.start_date,
      end_date: program.end_date,
      meeting_days: program.meeting_days || [],
      meeting_start_time: program.meeting_start_time,
      meeting_end_time: program.meeting_end_time,
      season: program.season,
      registration_start_date: program.registration_start_date,
      registration_end_date: program.registration_end_date,
      provider_id: program.provider_id,
      provider_verified: false,
      inserted_at: program.inserted_at || now,
      updated_at: program.updated_at || now
    })
    |> KlassHero.Repo.insert!()

    program
  end

  # Trigger: sessions modal reads from provider_session_details (event-driven projection)
  # Why: projections are disabled in the test env (start_projections: false); we start
  #      a per-test named projection, grant it sandbox access, then rebuild from the
  #      write tables — the same path the supervisor uses in non-test envs.
  # Outcome: read table converges to the write-table state so ListProgramSessions
  #          returns the inserted session.
  defp seed_program_with_session!(provider, attrs) do
    attrs_map = Map.new(attrs)
    title = Map.get(attrs_map, :title, "Test Program")

    program = insert_program_with_listing(provider_id: provider.id, title: title)

    KlassHero.Factory.insert(:program_session_schema,
      program_id: program.id,
      session_date: ~D[2026-05-01],
      start_time: ~T[15:00:00],
      end_time: ~T[16:00:00],
      status: "scheduled"
    )

    name = :"provider_session_details_#{System.unique_integer([:positive])}"
    pid = start_supervised!({ProviderSessionDetails, name: name})
    # Trigger: the GenServer's handle_continue/handle_call callbacks run in its
    #          own process, which the Ecto sandbox doesn't own by default (async
    #          test connection is owned by the test pid).
    # Why: grant the projection access to the same checked-out connection so its
    #      bootstrap query can see the write rows we just inserted. The initial
    #      handle_continue(:bootstrap) may race ahead of this allow and fail —
    #      the projection self-heals via :retry_bootstrap after 1s, but we also
    #      force a synchronous rebuild below to avoid that wait.
    # Outcome: the projection can read from and write to the test's sandboxed DB.
    :ok = Sandbox.allow(Repo, self(), pid)
    :ok = ProviderSessionDetails.rebuild(name)

    program
  end

  describe "overview section" do
    test "renders dashboard with business name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      # Verify main heading is present (business name + Dashboard)
      assert has_element?(view, "h1")
      # Verify navigation tabs are present
      assert has_element?(view, "nav")
    end

    test "displays stat cards", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      # Verify stat card grid is present (4 stat cards in overview)
      assert has_element?(view, ".grid")
    end

    test "displays business profile card", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      # Verify business profile section exists with Edit Profile link
      assert has_element?(view, "a", "Edit Profile")
    end

    test "shows no subscription plan management link", %{conn: conn} do
      # Provider tiers removed (ADR-0004): no plan to manage
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")
      refute has_element?(view, "#subscription-cta")
      refute has_element?(view, ~s(a[href="/provider/subscription"]))
    end

    test "displays business logo when logo_url is set", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      # Factory sets logo_url by default, so real logo image should show
      assert has_element?(view, "#business-logo")
      refute has_element?(view, "#business-logo-placeholder")
    end

    test "displays initials placeholder when no logo_url", %{conn: conn, provider: provider} do
      # Remove logo_url from the provider
      provider
      |> Ecto.Changeset.change(logo_url: nil)
      |> KlassHero.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      assert has_element?(view, "#business-logo-placeholder")
      refute has_element?(view, "#business-logo")
    end

    test "shows 'Not Verified' status when no documents submitted", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      assert has_element?(view, "#verification-status", "Not Verified")
    end

    test "shows 'Pending Review' status when documents are pending", %{
      conn: conn,
      provider: provider
    } do
      KlassHero.Factory.insert(:verification_document_schema,
        provider_profile_id: provider.id,
        document_type: :business_registration,
        status: :pending
      )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      assert has_element?(view, "#verification-status", "Pending Review")
    end

    test "shows 'Verified' status when provider is verified", %{conn: conn, provider: provider} do
      provider
      |> Ecto.Changeset.change(
        verified: true,
        verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )
      |> KlassHero.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      assert has_element?(view, "#verification-status", "Verified")
      refute has_element?(view, "#verification-status", "Not Verified")
      # locks the Theme.status_badge(:available) migration (AA-safe -800 shade)
      assert has_element?(view, "#verification-status.text-green-800")
    end
  end

  describe "new program button gating" do
    test "disables 'New Program' button when provider is not verified", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      assert has_element?(view, "#new-program-btn[disabled]")
      assert has_element?(view, "#new-program-tooltip")
    end

    test "enables 'New Program' button when provider is verified", %{
      conn: conn,
      provider: provider
    } do
      provider
      |> Ecto.Changeset.change(
        verified: true,
        verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )
      |> KlassHero.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      refute has_element?(view, "#new-program-btn[disabled]")
      refute has_element?(view, "#new-program-tooltip")
    end

    test "shows tooltip explaining verification requirement", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      html = render(view)
      assert html =~ "Complete business verification to create programs."
    end
  end

  describe "tab navigation" do
    test "navigates to team section via tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      # Click on Team & Profiles tab — now a separate LiveView, so a full navigate
      view |> element("a", "Team & Profiles") |> render_click()

      # Verify navigation to the team sub-LiveView
      assert_redirect(view, ~p"/provider/dashboard/team")
    end

    test "navigates to programs section via tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      # Click on My Programs tab — separate LiveView, full navigate
      view |> element("a", "My Programs") |> render_click()

      # Verify navigation to the programs sub-LiveView
      assert_redirect(view, ~p"/provider/dashboard/programs")
    end
  end

  describe "team section" do
    test "renders team section with team members", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      # Verify Add Team Member button is present
      assert has_element?(view, "button", "Add Team Member")
    end

    test "resend invitation shows success flash for failed invitation", %{
      conn: conn,
      provider: provider
    } do
      setup_test_integration_events()

      _staff =
        ProviderFixtures.staff_member_fixture(%{
          provider_id: provider.id,
          email: "staff@example.com",
          first_name: "Resend",
          last_name: "Test",
          invitation_status: :failed,
          invitation_token_hash: :crypto.hash(:sha256, "old-token")
        })

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      view
      |> element("button", "Resend")
      |> render_click()

      assert render(view) =~ "Invitation resent successfully."
    end

    test "resend invitation for accepted member shows specific error", %{
      conn: conn,
      provider: provider
    } do
      staff =
        ProviderFixtures.staff_member_fixture(%{
          provider_id: provider.id,
          email: "accepted@example.com",
          first_name: "Already",
          last_name: "Accepted",
          invitation_status: :accepted
        })

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      # Accepted members don't show resend button, so push event directly
      render_hook(view, "resend_invitation", %{"id" => staff.id})

      assert render(view) =~ "This invitation cannot be resent"
    end
  end

  describe "programs section" do
    test "renders programs section with table", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      # Verify programs table exists
      assert has_element?(view, "table")
      # Verify search input exists
      assert has_element?(view, "input[name=\"search\"]")
      # Verify staff filter exists
      assert has_element?(view, "select[name=\"staff_filter\"]")
    end

    test "programs visible after navigating from team tab", %{conn: conn, provider: provider} do
      insert_program_with_listing(
        title: "Soccer Academy",
        category: "sports",
        provider_id: provider.id
      )

      # Mount on team tab first
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      # Navigate to programs tab — separate LiveView, full navigate + remount
      view |> element("a", "My Programs") |> render_click()
      assert_redirect(view, ~p"/provider/dashboard/programs")

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      assert has_element?(view, "td", "Soccer Academy")
    end

    test "staff filter shows staff members after tab navigation", %{
      conn: conn,
      provider: provider
    } do
      ProviderFixtures.staff_member_fixture(
        provider_id: provider.id,
        first_name: "Alice",
        last_name: "Smith"
      )

      # Mount on team tab first
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/team")

      # Navigate to programs tab — separate LiveView, full navigate + remount
      view |> element("a", "My Programs") |> render_click()
      assert_redirect(view, ~p"/provider/dashboard/programs")

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      # Staff filter dropdown should include the staff member
      assert render(view) =~ "Alice Smith"
    end

    test "filters programs by search query", %{conn: conn, provider: provider} do
      # Create programs for this provider
      insert_program_with_listing(
        title: "Soccer Academy",
        category: "sports",
        provider_id: provider.id
      )

      insert_program_with_listing(
        title: "Art Class",
        category: "arts",
        provider_id: provider.id
      )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      # Search for "Soccer" which should match "Soccer Academy"
      view |> render_change("search_programs", %{"search" => "Soccer"})

      # Verify filtered result is present
      assert has_element?(view, "td", "Soccer Academy")
      # Art Class should not be shown
      refute has_element?(view, "td", "Art Class")
    end

    test "shows empty state when provider has no programs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      # The provider was just created and has no programs
      # Table should exist but be empty (header row only)
      assert has_element?(view, "table")
    end
  end

  describe "roster modal with tabs" do
    setup %{provider: provider} do
      program =
        insert_program_with_listing(
          provider_id: provider.id,
          title: "Test Program"
        )

      %{program: program}
    end

    test "shows enrolled and invites tabs when roster opened", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#view-roster-#{program.id}") |> render_click()

      assert has_element?(view, "#roster-modal")
      assert has_element?(view, "#roster-tab-enrolled")
      assert has_element?(view, "#roster-tab-invites")
    end

    test "enrolled tab is active by default", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#view-roster-#{program.id}") |> render_click()

      assert has_element?(view, "#roster-tab-enrolled[aria-selected=true]")
    end

    test "broadcast button disabled when no enrollments", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#view-roster-#{program.id}") |> render_click()

      assert has_element?(view, "#broadcast-#{program.id}[disabled]")
      assert has_element?(view, ~s(#broadcast-#{program.id}[title="No enrolled parents"]))
    end

    test "broadcast button links to broadcast page when enrollments exist", %{
      conn: conn,
      program: program
    } do
      parent = KlassHero.Factory.insert(:parent_profile_schema)

      KlassHero.Factory.insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#view-roster-#{program.id}") |> render_click()

      assert has_element?(view, ~s(a[href="/provider/programs/#{program.id}/broadcast"]))
      refute has_element?(view, "#broadcast-#{program.id}[disabled]")
    end

    test "switches to invites tab", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#view-roster-#{program.id}") |> render_click()
      view |> element("#roster-tab-invites") |> render_click()

      assert has_element?(view, "#roster-tab-invites[aria-selected=true]")
      assert has_element?(view, "#invites-tab-content")
    end

    test "invites tab shows empty state when no invites", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#view-roster-#{program.id}") |> render_click()
      view |> element("#roster-tab-invites") |> render_click()

      assert has_element?(view, "#invites-empty")
    end
  end

  describe "invites tab content" do
    setup %{provider: provider} do
      program =
        insert_program_with_listing(
          provider_id: provider.id,
          title: "Test Program"
        )

      {:ok, _invite} =
        KlassHero.Enrollment.create_invite(%{
          program_id: program.id,
          provider_id: provider.id,
          child_first_name: "Jane",
          child_last_name: "Smith",
          child_date_of_birth: ~D[2015-06-15],
          guardian_email: "parent@test.com"
        })

      %{program: program}
    end

    test "shows invite rows with child name, email, status", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#view-roster-#{program.id}") |> render_click()
      view |> element("#roster-tab-invites") |> render_click()

      assert has_element?(view, "#invites-table")
      html = render(view)
      assert html =~ "Jane"
      assert html =~ "Smith"
      assert html =~ "parent@test.com"
    end

    test "shows resend button for pending invite", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#view-roster-#{program.id}") |> render_click()
      view |> element("#roster-tab-invites") |> render_click()

      assert has_element?(view, "[phx-click=resend_invite]")
    end

    test "shows remove button for pending invite", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#view-roster-#{program.id}") |> render_click()
      view |> element("#roster-tab-invites") |> render_click()

      assert has_element?(view, "[phx-click=delete_invite]")
    end
  end

  describe "invite actions" do
    setup %{provider: provider} do
      program =
        insert_program_with_listing(
          provider_id: provider.id,
          title: "Test Program"
        )

      {:ok, _invite} =
        KlassHero.Enrollment.create_invite(%{
          program_id: program.id,
          provider_id: provider.id,
          child_first_name: "Jane",
          child_last_name: "Smith",
          child_date_of_birth: ~D[2015-06-15],
          guardian_email: "parent@test.com"
        })

      %{program: program}
    end

    test "resend invite shows success flash", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#view-roster-#{program.id}") |> render_click()
      view |> element("#roster-tab-invites") |> render_click()

      html = view |> element("[phx-click=resend_invite]") |> render_click()

      assert html =~ "Invite resent"
    end

    test "delete invite removes row from table", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#view-roster-#{program.id}") |> render_click()
      view |> element("#roster-tab-invites") |> render_click()

      assert has_element?(view, "#invites-table")

      view |> element("[phx-click=delete_invite]") |> render_click()

      assert has_element?(view, "#invites-empty")
    end
  end

  # ===========================================================================
  # Issue #546: manual single-invite form
  # ===========================================================================

  describe "single invite form" do
    setup %{provider: provider} do
      program =
        insert_program_with_listing(
          provider_id: provider.id,
          title: "Single Invite Program"
        )

      %{program: program}
    end

    defp open_invites_tab(conn, program_id) do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      view |> element("#view-roster-#{program_id}") |> render_click()
      view |> element("#roster-tab-invites") |> render_click()
      view
    end

    test "defaults to single-invite mode with the form rendered", %{conn: conn, program: program} do
      view = open_invites_tab(conn, program.id)

      assert has_element?(view, "#invite-mode-single[aria-pressed=true]")
      assert has_element?(view, "#invite-mode-csv[aria-pressed=false]")
      assert has_element?(view, "#single-invite-form")
      # CSV upload form should NOT be present in single mode
      refute has_element?(view, "#csv-upload-form")
    end

    test "switches to CSV mode and back", %{conn: conn, program: program} do
      view = open_invites_tab(conn, program.id)

      view |> element("#invite-mode-csv") |> render_click()

      assert has_element?(view, "#invite-mode-csv[aria-pressed=true]")
      assert has_element?(view, "#csv-upload-form")
      refute has_element?(view, "#single-invite-form")

      view |> element("#invite-mode-single") |> render_click()

      assert has_element?(view, "#invite-mode-single[aria-pressed=true]")
      assert has_element?(view, "#single-invite-form")
    end

    test "ignores switch_invite_mode with an unknown mode without crashing", %{
      conn: conn,
      program: program
    } do
      view = open_invites_tab(conn, program.id)

      # Bypass the markup (which only emits "single"/"csv") and push a
      # raw event, simulating a buggy Hook or a crafted channel message.
      render_hook(view, "switch_invite_mode", %{"mode" => "hacked"})

      # Socket stays alive and the mode is unchanged from its default.
      assert has_element?(view, "#invite-mode-single[aria-pressed=true]")
      assert has_element?(view, "#single-invite-form")
    end

    test "shows inline error on invalid email via phx-change", %{conn: conn, program: program} do
      view = open_invites_tab(conn, program.id)

      html =
        view
        |> form("#single-invite-form",
          single_invite: %{
            "program_id" => program.id,
            "child_first_name" => "Emma",
            "child_last_name" => "Schmidt",
            "child_date_of_birth" => "2016-03-15",
            "guardian_email" => "not-an-email"
          }
        )
        |> render_change()

      assert html =~ "must be a valid email"
    end

    test "successful submit adds the invite to the table and flashes", %{
      conn: conn,
      program: program
    } do
      view = open_invites_tab(conn, program.id)

      html =
        view
        |> form("#single-invite-form",
          single_invite: %{
            "program_id" => program.id,
            "child_first_name" => "Emma",
            "child_last_name" => "Schmidt",
            "child_date_of_birth" => "2016-03-15",
            "guardian_email" => "new-parent@example.com"
          }
        )
        |> render_submit()

      assert html =~ "Invite sent"
      assert has_element?(view, "#invites-table")
      assert render(view) =~ "Emma"
      assert render(view) =~ "new-parent@example.com"
    end

    test "duplicate submit surfaces an error flash and adds no new row", %{
      conn: conn,
      provider: provider,
      program: program
    } do
      # Seed an existing invite matching the form submission
      {:ok, _} =
        KlassHero.Enrollment.create_invite(%{
          program_id: program.id,
          provider_id: provider.id,
          child_first_name: "Emma",
          child_last_name: "Schmidt",
          child_date_of_birth: ~D[2016-03-15],
          guardian_email: "existing@example.com"
        })

      view = open_invites_tab(conn, program.id)

      html =
        view
        |> form("#single-invite-form",
          single_invite: %{
            "program_id" => program.id,
            "child_first_name" => "Emma",
            "child_last_name" => "Schmidt",
            "child_date_of_birth" => "2016-03-15",
            "guardian_email" => "existing@example.com"
          }
        )
        |> render_submit()

      assert html =~ "already exists"

      # Still only one invite in the table
      rendered = render(view)
      existing_count = rendered |> String.split("existing@example.com") |> length() |> Kernel.-(1)
      assert existing_count == 1
    end
  end

  # ===========================================================================
  # T3: close_roster handler
  # ===========================================================================

  describe "close roster" do
    setup %{provider: provider} do
      program =
        insert_program_with_listing(
          provider_id: provider.id,
          title: "Test Program"
        )

      %{program: program}
    end

    test "closing roster hides modal", %{conn: conn, program: program} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#view-roster-#{program.id}") |> render_click()
      assert has_element?(view, "#roster-modal")

      view |> element("button[phx-click=close_roster]") |> render_click()
      refute has_element?(view, "#roster-modal")
    end
  end

  describe "sessions modal" do
    test "clicking Sessions opens the modal with the program's sessions", %{
      conn: conn,
      provider: provider
    } do
      program = seed_program_with_session!(provider, title: "Judo")

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view
      |> element(~s|button[phx-click="view_sessions"][phx-value-program-id="#{program.id}"]|)
      |> render_click()

      assert has_element?(view, "#sessions-modal")
      assert render(view) =~ "Judo"

      view |> element("#sessions-modal button[phx-click='close_sessions']") |> render_click()
      refute has_element?(view, "#sessions-modal")
    end
  end

  # ===========================================================================
  # T4/T6: invite error paths
  # ===========================================================================

  describe "invite error paths" do
    setup %{provider: provider} do
      program =
        insert_program_with_listing(
          provider_id: provider.id,
          title: "Test Program"
        )

      %{program: program}
    end

    test "enrolled invite does not show action buttons", %{
      conn: conn,
      provider: provider,
      program: program
    } do
      {:ok, _} =
        KlassHero.Enrollment.create_invite(%{
          program_id: program.id,
          provider_id: provider.id,
          child_first_name: "Jane",
          child_last_name: "Smith",
          child_date_of_birth: ~D[2015-06-15],
          guardian_email: "enrolled@test.com"
        })

      # Walk through the state machine to enrolled
      {:ok, [invite]} = KlassHero.Enrollment.list_program_invites(program.id)

      {:ok, sent} =
        KlassHero.Enrollment.transition_invite(invite, %{
          status: "invite_sent",
          invite_token: "tok",
          invite_sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, registered} =
        KlassHero.Enrollment.transition_invite(sent, %{
          status: "registered",
          registered_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, _enrolled} =
        KlassHero.Enrollment.transition_invite(registered, %{
          status: "enrolled",
          enrolled_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      view |> element("#view-roster-#{program.id}") |> render_click()
      view |> element("#roster-tab-invites") |> render_click()

      refute has_element?(view, "[phx-click=resend_invite]")
      refute has_element?(view, "[phx-click=delete_invite]")
    end

    test "resend shows error when invite deleted concurrently", %{
      conn: conn,
      provider: provider,
      program: program
    } do
      {:ok, _} =
        KlassHero.Enrollment.create_invite(%{
          program_id: program.id,
          provider_id: provider.id,
          child_first_name: "Jane",
          child_last_name: "Smith",
          child_date_of_birth: ~D[2015-06-15],
          guardian_email: "concurrent@test.com"
        })

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      view |> element("#view-roster-#{program.id}") |> render_click()
      view |> element("#roster-tab-invites") |> render_click()

      # Delete the invite from the DB while the DOM still has the button
      {:ok, [invite]} = KlassHero.Enrollment.list_program_invites(program.id)
      :ok = KlassHero.Enrollment.delete_invite(invite.id, invite.provider_id)

      view |> element("[phx-click=resend_invite]") |> render_click()

      assert_flash(view, :error, "Failed to resend invite.")
    end

    test "delete shows error when invite already removed", %{
      conn: conn,
      provider: provider,
      program: program
    } do
      {:ok, _} =
        KlassHero.Enrollment.create_invite(%{
          program_id: program.id,
          provider_id: provider.id,
          child_first_name: "Jane",
          child_last_name: "Smith",
          child_date_of_birth: ~D[2015-06-15],
          guardian_email: "removed@test.com"
        })

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      view |> element("#view-roster-#{program.id}") |> render_click()
      view |> element("#roster-tab-invites") |> render_click()

      # Delete the invite from DB while the DOM still shows it
      {:ok, [invite]} = KlassHero.Enrollment.list_program_invites(program.id)
      :ok = KlassHero.Enrollment.delete_invite(invite.id, invite.provider_id)

      view |> element("[phx-click=delete_invite]") |> render_click()

      assert_flash(view, :error, "Invite not found.")
    end
  end

  # ===========================================================================
  # T1/T2: CSV import handler + error rendering
  # ===========================================================================

  describe "CSV import" do
    @csv_defaults %{
      first: "Alice",
      last: "Smith",
      dob: "1/1/2016",
      parent_first: "Bob",
      parent_last: "Smith",
      email: "parent@example.com",
      parent2_first: "",
      parent2_last: "",
      parent2_email: "",
      grade: "",
      school: "",
      has_medical: "",
      medical: "",
      nut_allergy: "",
      photo_marketing: "",
      photo_social: "",
      program: "Ballsports & Parkour",
      instructor: "",
      season: "Test Season"
    }

    @csv_field_order ~w(first last dob parent_first parent_last email
      parent2_first parent2_last parent2_email grade school has_medical
      medical nut_allergy photo_marketing photo_social program instructor season)a

    @csv_header_row [
      "Participant information: First name",
      "Participant information: Last name",
      "Participant information: Date of birth",
      "Parent/guardian information: First name",
      "Parent/guardian information: Last name",
      "Parent/guardian information: Email address",
      "Parent/guardian 2 information: First name",
      "Parent/guardian 2 information: Last name",
      "Parent/guardian 2 information: Email address",
      "School information: Grade",
      "School information: Name",
      "Medical/allergy information: Do you have medical conditions and special needs?",
      "Medical/allergy information: Medical conditions and special needs",
      "Medical/allergy information: Nut allergy",
      ~s|Photography/video release permission: I agree that photos showing my child at camp may appear in marketing materials (e.g. posters, website) free of charge. this agreement is valid for unlimited time for all types of existing media and those that may be created.|,
      ~s|Photography/video release permission: I agree that photos and films showing my child participating in activities may appear for marketing purposes on prime youth's social media channels (e.g. facebook, instagram, youtube) free of charge, valid for unlimited time and without revealing my children's identity.|,
      "Program",
      "Instructor",
      "Season"
    ]

    setup %{provider: provider} do
      program =
        insert_program_with_listing(
          provider_id: provider.id,
          title: "Ballsports & Parkour"
        )

      %{program: program}
    end

    defp build_csv(rows) do
      headers = Enum.map_join(@csv_header_row, ",", &csv_escape/1)

      data_rows =
        Enum.map(rows, fn row ->
          merged = Map.merge(@csv_defaults, row)
          Enum.map_join(@csv_field_order, ",", &csv_escape(merged[&1]))
        end)

      [headers | data_rows] |> Enum.join("\n")
    end

    defp csv_escape(value) when is_binary(value) do
      if String.contains?(value, [",", "\"", "\n"]) do
        "\"" <> String.replace(value, "\"", "\"\"") <> "\""
      else
        value
      end
    end

    defp csv_escape(value), do: to_string(value)

    defp navigate_to_invites_tab(view, program) do
      view |> element("#view-roster-#{program.id}") |> render_click()
      view |> element("#roster-tab-invites") |> render_click()
      # Issue #546: Invites tab now defaults to the single-invite form; switch to
      # CSV mode so the upload form is present for these CSV-specific tests.
      view |> element("#invite-mode-csv") |> render_click()
    end

    test "successful import shows flash and refreshes invites", %{
      conn: conn,
      program: program
    } do
      csv_content = build_csv([%{first: "Emma", last: "Schmidt", email: "emma@test.com"}])

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      navigate_to_invites_tab(view, program)

      csv_file =
        file_input(view, "#csv-upload-form", :csv_file, [
          %{
            name: "import.csv",
            content: csv_content,
            type: "text/csv"
          }
        ])

      render_upload(csv_file, "import.csv")
      render_submit(view, "import_csv", %{})

      assert_flash(view, :info, "Imported 1 family.")
      assert has_element?(view, "#invites-table")
      refute has_element?(view, "#import-errors")
    end

    test "import with validation errors shows import-errors div and no-rows flash", %{
      conn: conn,
      program: program
    } do
      csv_content = build_csv([%{email: ""}])

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      navigate_to_invites_tab(view, program)

      csv_file =
        file_input(view, "#csv-upload-form", :csv_file, [
          %{
            name: "bad.csv",
            content: csv_content,
            type: "text/csv"
          }
        ])

      render_upload(csv_file, "bad.csv")
      render_submit(view, "import_csv", %{})

      # All-failed CSV: error flash + #import-errors list rendered
      assert_flash(view, :error, ~r/No rows imported/)
      assert has_element?(view, "#import-errors")
      html = render(view)
      assert html =~ "Rows with errors"
    end

    test "import with parse errors (bad headers) shows import-errors div with fatal message", %{
      conn: conn,
      program: program
    } do
      csv_content = "Wrong,Headers\nval1,val2\n"

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      navigate_to_invites_tab(view, program)

      csv_file =
        file_input(view, "#csv-upload-form", :csv_file, [
          %{
            name: "bad_headers.csv",
            content: csv_content,
            type: "text/csv"
          }
        ])

      render_upload(csv_file, "bad_headers.csv")
      render_submit(view, "import_csv", %{})

      # Whole-file fatal: no flash, just #import-errors with error detail
      assert has_element?(view, "#import-errors")
      html = render(view)
      assert html =~ "Rows with errors"
    end

    test "mixed CSV shows partial-success flash and renders failed rows", %{
      conn: conn,
      program: program
    } do
      # First row valid, second row invalid (missing email)
      csv_content =
        build_csv([
          %{first: "Alice", last: "Smith", email: "alice@example.com"},
          %{first: "Bob", last: "Smith", email: ""}
        ])

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      navigate_to_invites_tab(view, program)

      csv_file =
        file_input(view, "#csv-upload-form", :csv_file, [
          %{
            name: "mixed.csv",
            content: csv_content,
            type: "text/csv"
          }
        ])

      render_upload(csv_file, "mixed.csv")
      render_submit(view, "import_csv", %{})

      # Partial-success: info flash for imported count, error list for failed rows
      assert_flash(view, :info, ~r/Imported 1 family/)
      html = render(view)
      assert html =~ "could not be processed"
      assert has_element?(view, "#import-errors")
      assert html =~ "Rows with errors"
    end

    test "submitting without file shows no-file flash", %{
      conn: conn,
      program: program
    } do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      navigate_to_invites_tab(view, program)

      render_submit(view, "import_csv", %{})

      assert_flash(view, :error, "No file selected.")
    end
  end

  # ===========================================================================
  # Program start/end time parsing (#282)
  # ===========================================================================

  describe "program time parsing on save" do
    setup %{provider: provider} do
      provider
      |> Ecto.Changeset.change(
        verified: true,
        verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )
      |> KlassHero.Repo.update!()

      %{}
    end

    defp valid_program_params(overrides \\ %{}) do
      Map.merge(
        %{
          "title" => "Time Test Program",
          "category" => "sports",
          "description" => "A test program",
          "price" => "50.00",
          "meeting_start_time" => "09:00",
          "meeting_end_time" => "11:00"
        },
        overrides
      )
    end

    test "saves program with HH:MM time format from initial form submission", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      # Open the new program form
      view |> element("#new-program-btn") |> render_click()

      # Submit with HH:MM format (as HTML time input sends)
      view
      |> render_submit("save_program", %{
        "program_schema" => valid_program_params(),
        "enrollment_policy" => %{},
        "participant_policy" => %{}
      })

      refute has_element?(view, "#program-form")
    end

    test "saves program with HH:MM:SS time format from re-rendered form", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view |> element("#new-program-btn") |> render_click()

      # Submit with HH:MM:SS format (as Time.to_iso8601/1 produces after a phx-change cycle)
      view
      |> render_submit("save_program", %{
        "program_schema" =>
          valid_program_params(%{
            "meeting_start_time" => "09:00:00",
            "meeting_end_time" => "11:00:00"
          }),
        "enrollment_policy" => %{},
        "participant_policy" => %{}
      })

      refute has_element?(view, "#program-form")
    end

    test "editing program with existing times and re-saving succeeds", %{
      conn: conn,
      provider: provider
    } do
      program =
        insert_program_with_listing(
          provider_id: provider.id,
          title: "Existing Timed Program",
          meeting_start_time: ~T[14:30:00],
          meeting_end_time: ~T[16:00:00]
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      # Open edit form (populates times as HH:MM:SS via Time.to_iso8601/1)
      view
      |> element(~s([phx-click="edit_program"][phx-value-id="#{program.id}"]))
      |> render_click()

      assert has_element?(view, "#program-form")

      # Re-submit with HH:MM:SS values (simulating what the form sends after edit_program)
      view
      |> render_submit("save_program", %{
        "program_schema" =>
          valid_program_params(%{
            "title" => "Existing Timed Program",
            "meeting_start_time" => "14:30:00",
            "meeting_end_time" => "16:00:00"
          }),
        "enrollment_policy" => %{},
        "participant_policy" => %{}
      })

      assert_flash(view, :info, "Program updated successfully.")
    end
  end

  describe "edit program - clearing participant restrictions" do
    setup %{provider: provider} do
      provider
      |> Ecto.Changeset.change(
        verified: true,
        verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )
      |> KlassHero.Repo.update!()

      %{}
    end

    test "clears stored restrictions when all fields submitted blank", %{
      conn: conn,
      provider: provider
    } do
      program =
        insert_program_with_listing(
          provider_id: provider.id,
          title: "Restricted Program"
        )

      {:ok, _policy} =
        KlassHero.Enrollment.set_participant_policy(%{
          program_id: program.id,
          eligibility_at: "registration",
          min_age_months: 60,
          max_age_months: 144,
          allowed_genders: ["female"],
          min_grade: 1,
          max_grade: 4
        })

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view
      |> element(~s([phx-click="edit_program"][phx-value-id="#{program.id}"]))
      |> render_click()

      assert has_element?(view, "#program-form")

      view
      |> render_submit("save_program", %{
        "program_schema" =>
          valid_program_params(%{
            "title" => "Restricted Program",
            "meeting_start_time" => "09:00",
            "meeting_end_time" => "11:00"
          }),
        "enrollment_policy" => %{},
        "participant_policy" => %{
          "eligibility_at" => "registration",
          "min_age_months" => "",
          "max_age_months" => "",
          "allowed_genders" => [""],
          "min_grade" => "",
          "max_grade" => ""
        }
      })

      assert_flash(view, :info, "Program updated successfully.")

      assert {:ok, cleared} = KlassHero.Enrollment.get_participant_policy(to_string(program.id))
      assert cleared.min_age_months == nil
      assert cleared.max_age_months == nil
      assert cleared.allowed_genders == []
      assert cleared.min_grade == nil
      assert cleared.max_grade == nil
    end

    test "upserts an empty policy when no prior policy existed", %{
      conn: conn,
      provider: provider
    } do
      program =
        insert_program_with_listing(
          provider_id: provider.id,
          title: "Unrestricted Program"
        )

      assert {:error, :not_found} =
               KlassHero.Enrollment.get_participant_policy(to_string(program.id))

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")

      view
      |> element(~s([phx-click="edit_program"][phx-value-id="#{program.id}"]))
      |> render_click()

      view
      |> render_submit("save_program", %{
        "program_schema" =>
          valid_program_params(%{
            "title" => "Unrestricted Program",
            "meeting_start_time" => "09:00",
            "meeting_end_time" => "11:00"
          }),
        "enrollment_policy" => %{},
        "participant_policy" => %{
          "eligibility_at" => "registration",
          "min_age_months" => "",
          "max_age_months" => "",
          "allowed_genders" => [""],
          "min_grade" => "",
          "max_grade" => ""
        }
      })

      assert_flash(view, :info, "Program updated successfully.")

      assert {:ok, policy} = KlassHero.Enrollment.get_participant_policy(to_string(program.id))
      assert policy.min_age_months == nil
      assert policy.max_age_months == nil
      assert policy.allowed_genders == []
      assert policy.min_grade == nil
      assert policy.max_grade == nil
    end
  end

  # ===========================================================================
  # T4: roster send message button
  # ===========================================================================

  describe "roster send message button" do
    setup %{provider: provider} do
      program =
        insert_program_with_listing(
          provider_id: provider.id,
          title: "Message Test Program"
        )

      %{program: program}
    end

    test "shows enabled message button for confirmed enrollment", %{
      conn: conn,
      program: program
    } do
      parent = KlassHero.Factory.insert(:parent_profile_schema)
      child = KlassHero.Factory.insert(:child_schema)

      enrollment =
        KlassHero.Factory.insert(:enrollment_schema,
          program_id: program.id,
          child_id: child.id,
          parent_id: parent.id,
          status: "confirmed"
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      view |> element("#view-roster-#{program.id}") |> render_click()

      assert has_element?(view, "#send-message-#{enrollment.id}")
      refute has_element?(view, "#send-message-#{enrollment.id}[disabled]")
    end

    test "shows disabled message button for pending enrollment", %{
      conn: conn,
      program: program
    } do
      parent = KlassHero.Factory.insert(:parent_profile_schema)
      child = KlassHero.Factory.insert(:child_schema)

      enrollment =
        KlassHero.Factory.insert(:enrollment_schema,
          program_id: program.id,
          child_id: child.id,
          parent_id: parent.id,
          status: "pending"
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      view |> element("#view-roster-#{program.id}") |> render_click()

      assert has_element?(view, "#send-message-#{enrollment.id}[disabled]")
    end

    test "clicking send message navigates to messaging page", %{
      conn: conn,
      program: program
    } do
      parent = KlassHero.Factory.insert(:parent_profile_schema)
      child = KlassHero.Factory.insert(:child_schema)

      enrollment =
        KlassHero.Factory.insert(:enrollment_schema,
          program_id: program.id,
          child_id: child.id,
          parent_id: parent.id,
          status: "confirmed"
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      view |> element("#view-roster-#{program.id}") |> render_click()

      view |> element("#send-message-#{enrollment.id}") |> render_click()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/provider/messages/"
    end

    test "shows enabled message buttons for former starter-tier provider", %{conn: conn} do
      # Provider tiers removed (ADR-0004): every provider can initiate messaging
      user = KlassHero.AccountsFixtures.user_fixture(%{intended_roles: [:provider]})

      provider =
        KlassHero.Factory.insert(:provider_profile_schema, identity_id: user.id)

      conn = log_in_user(conn, user)

      program =
        insert_program_with_listing(
          provider_id: provider.id,
          title: "Starter Program"
        )

      parent = KlassHero.Factory.insert(:parent_profile_schema)
      child = KlassHero.Factory.insert(:child_schema)

      enrollment =
        KlassHero.Factory.insert(:enrollment_schema,
          program_id: program.id,
          child_id: child.id,
          parent_id: parent.id,
          status: "confirmed"
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard/programs")
      view |> element("#view-roster-#{program.id}") |> render_click()

      assert has_element?(view, "#send-message-#{enrollment.id}")
      refute has_element?(view, "#send-message-#{enrollment.id}[disabled]")
    end
  end

  describe "cross-navigation for dual-role users" do
    setup %{conn: conn} do
      %{user: user} = fixtures = KlassHero.ProviderFixtures.dual_role_user_fixture()
      Map.put(fixtures, :conn, log_in_user(conn, user))
    end

    test "shows link to staff dashboard for dual-role users", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")
      assert has_element?(view, "#cross-nav-staff-link")
    end
  end

  describe "cross-navigation for provider-only users" do
    test "does NOT show link to staff dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")
      refute has_element?(view, "#cross-nav-staff-link")
    end
  end

  describe "profile completion banner" do
    test "does NOT show banner for active (complete) profile", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")
      refute has_element?(view, "#profile-completion-banner")
    end
  end

  describe "profile completion banner for draft profile" do
    setup :register_and_log_in_draft_provider

    test "shows banner for draft profile", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")
      assert has_element?(view, "#profile-completion-banner")
      assert has_element?(view, ~s(a[href="/provider/complete-profile"]))
    end
  end

  describe "pending enrollments card" do
    test "shows empty state when no pending enrollments", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      assert has_element?(view, "#pending-enrollments-card")
      assert render(view) =~ "No pending enrollments right now."
    end

    test "renders a row per pending enrollment for this provider", %{conn: conn, provider: provider} do
      program = insert_program_with_listing(provider_id: provider.id, title: "Soccer Camp")
      {child, parent} = KlassHero.Factory.insert_child_with_guardian()

      enrollment =
        KlassHero.Factory.insert(:enrollment_schema,
          program_id: program.id,
          parent_id: parent.id,
          child_id: child.id,
          status: :pending
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      assert has_element?(view, "#pending-enrollment-#{enrollment.id}")
      assert has_element?(view, "#approve-enrollment-#{enrollment.id}")
      assert render(view) =~ "Soccer Camp"
    end

    test "does not show pending enrollments from another provider", %{conn: conn} do
      other_provider = KlassHero.Factory.insert(:provider_profile_schema)
      other_program = KlassHero.Factory.insert(:program_schema, provider_id: other_provider.id)

      enrollment =
        KlassHero.Factory.insert(:enrollment_schema, program_id: other_program.id, status: :pending)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      refute has_element?(view, "#pending-enrollment-#{enrollment.id}")
    end

    test "approving a pending enrollment confirms it in the DB and flashes success",
         %{conn: conn, provider: provider} do
      program = insert_program_with_listing(provider_id: provider.id)
      {child, parent} = KlassHero.Factory.insert_child_with_guardian()

      enrollment =
        KlassHero.Factory.insert(:enrollment_schema,
          program_id: program.id,
          parent_id: parent.id,
          child_id: child.id,
          status: :pending
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      view
      |> element("#approve-enrollment-#{enrollment.id}")
      |> render_click()

      assert render(view) =~ "Enrollment approved"

      {:ok, reloaded} = KlassHero.Enrollment.get_enrollment(enrollment.id)
      assert reloaded.status == :confirmed
    end

    test "card refreshes when an :enrollment_confirmed event arrives for this provider",
         %{conn: conn, provider: provider} do
      program = insert_program_with_listing(provider_id: provider.id)
      {child, parent} = KlassHero.Factory.insert_child_with_guardian()

      enrollment =
        KlassHero.Factory.insert(:enrollment_schema,
          program_id: program.id,
          parent_id: parent.id,
          child_id: child.id,
          status: :pending
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      assert has_element?(view, "#pending-enrollment-#{enrollment.id}")

      enrollment
      |> Ecto.Changeset.change(%{
        status: :confirmed,
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()

      event =
        DomainEvent.new(
          :enrollment_confirmed,
          enrollment.id,
          :enrollment,
          %{provider_id: provider.id}
        )

      emit_domain_event(view, event)
      _ = render(view)

      refute has_element?(view, "#pending-enrollment-#{enrollment.id}")
    end

    test "in-memory dedup drops the confirmed card without re-querying the DB",
         %{conn: conn, provider: provider} do
      program = insert_program_with_listing(provider_id: provider.id)
      {child, parent} = KlassHero.Factory.insert_child_with_guardian()

      enrollment =
        KlassHero.Factory.insert(:enrollment_schema,
          program_id: program.id,
          parent_id: parent.id,
          child_id: child.id,
          status: :pending
        )

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")
      assert has_element?(view, "#pending-enrollment-#{enrollment.id}")

      # DB row deliberately left :pending. Only in-memory removal can drop the
      # card — a refresh would re-query and the still-pending row would reappear.
      event =
        DomainEvent.new(
          :enrollment_confirmed,
          enrollment.id,
          :enrollment,
          %{provider_id: provider.id, enrollment_id: enrollment.id}
        )

      emit_domain_event(view, event)
      _ = render(view)

      refute has_element?(view, "#pending-enrollment-#{enrollment.id}")

      {:ok, reloaded} = KlassHero.Enrollment.get_enrollment(enrollment.id)
      assert reloaded.status == :pending
    end

    test "falls back to a refresh when the confirmed id is not in local assigns",
         %{conn: conn, provider: provider} do
      program = insert_program_with_listing(provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")
      assert render(view) =~ "No pending enrollments right now."

      # A pending enrollment created after mount is absent from this tab's assigns
      # (simulates another tab acting before this one loaded).
      {child, parent} = KlassHero.Factory.insert_child_with_guardian()

      unseen =
        KlassHero.Factory.insert(:enrollment_schema,
          program_id: program.id,
          parent_id: parent.id,
          child_id: child.id,
          status: :pending
        )

      refute has_element?(view, "#pending-enrollment-#{unseen.id}")

      # Event carries an id NOT in assigns → miss → fallback refresh re-queries.
      event =
        DomainEvent.new(
          :enrollment_confirmed,
          Ecto.UUID.generate(),
          :enrollment,
          %{provider_id: provider.id, enrollment_id: Ecto.UUID.generate()}
        )

      emit_domain_event(view, event)
      _ = render(view)

      assert has_element?(view, "#pending-enrollment-#{unseen.id}")
    end

    test "approving an enrollment for another provider's program flashes an error",
         %{conn: conn} do
      other_provider = KlassHero.Factory.insert(:provider_profile_schema)
      other_program = KlassHero.Factory.insert(:program_schema, provider_id: other_provider.id)

      enrollment =
        KlassHero.Factory.insert(:enrollment_schema, program_id: other_program.id, status: :pending)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      render_hook(view, "approve_enrollment", %{"id" => enrollment.id})

      assert render(view) =~ "Not allowed"

      {:ok, reloaded} = KlassHero.Enrollment.get_enrollment(enrollment.id)
      assert reloaded.status == :pending
    end
  end

  # Regression coverage for the #904 split: shared chrome state that used to be set
  # by the god-module's mount/handle_params must be reproduced on every sub-LiveView.
  describe "shared dashboard chrome (post-split)" do
    for {tab, path} <- [
          {"overview", "/provider/dashboard"},
          {"team", "/provider/dashboard/team"},
          {"programs", "/provider/dashboard/programs"},
          {"edit", "/provider/dashboard/edit"}
        ] do
      test "#{tab} route marks the active provider-nav item (active_nav assigned)", %{conn: conn} do
        {:ok, view, _html} = live(conn, unquote(path))

        # active_nav drives pv_sidebar's aria-current; a nil assign (the regression)
        # leaves no nav item marked active on any route.
        assert has_element?(view, "[aria-current='page']")
      end
    end
  end
end
