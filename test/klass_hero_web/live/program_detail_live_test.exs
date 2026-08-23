defmodule KlassHeroWeb.ProgramDetailLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  describe "ProgramDetailLive mount validation" do
    test "renders program detail page with valid program ID", %{conn: conn} do
      program = insert(:program_schema, title: "Creative Art World")
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      assert has_element?(view, "h1", "Creative Art World")
    end

    # Any unresolvable id — bad format, unknown-but-valid UUID, zero, negative —
    # redirects to the index with the same "not found" flash.
    for id <- ["invalid", "550e8400-e29b-41d4-a716-446655449999", "0", "-1"] do
      @id id
      test "redirects with not-found flash for id #{id}", %{conn: conn} do
        assert {:error, {:redirect, %{to: path, flash: flash}}} =
                 live(conn, ~p"/programs/#{@id}")

        assert path == ~p"/programs"

        assert flash["error"] ==
                 "Program not found. It may have been removed or is no longer available."
      end
    end

    test "enroll_now button navigates to booking page", %{conn: conn} do
      program = insert(:program_schema)
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      view
      |> element("#book-now-button")
      |> render_click()

      assert_redirect(view, ~p"/programs/#{program.id}/booking")
    end

    test "enroll_now event shows error flash when registration is closed", %{conn: conn} do
      past_start = Date.add(Date.utc_today(), -30)
      past_end = Date.add(Date.utc_today(), -1)

      program =
        insert(:program_schema,
          registration_start_date: past_start,
          registration_end_date: past_end
        )

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      render_click(view, "enroll_now")

      assert_flash(view, :error, "Registration is not open for this program.")
    end

    test "enroll_now event shows error flash when registration is upcoming", %{conn: conn} do
      future_start = Date.add(Date.utc_today(), 7)
      future_end = Date.add(Date.utc_today(), 14)

      program =
        insert(:program_schema,
          registration_start_date: future_start,
          registration_end_date: future_end
        )

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      render_click(view, "enroll_now")

      assert_flash(view, :error, "Registration is not open for this program.")
    end

    test "back_to_programs event navigates to programs list", %{conn: conn} do
      program = insert(:program_schema)
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      view
      |> element("[phx-click='back_to_programs']")
      |> render_click()

      assert_redirect(view, ~p"/programs")
    end
  end

  describe "ProgramDetailLive cover image" do
    test "renders cover image in hero when cover_image_url is present", %{conn: conn} do
      program =
        insert(:program_schema,
          title: "Painting Class",
          cover_image_url: "https://example.com/painting.jpg"
        )

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      assert has_element?(view, "img[src='https://example.com/painting.jpg']")
    end

    test "renders gradient hero when no cover image", %{conn: conn} do
      program = insert(:program_schema, title: "Chess Club", cover_image_url: nil)
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      refute has_element?(view, "#program-cover-image")
      assert has_element?(view, "#program-hero")
    end
  end

  describe "hero info overlay" do
    test "renders title and schedule info with cover image", %{conn: conn} do
      program =
        insert(:program_schema,
          title: "Yoga for Kids",
          cover_image_url: "https://example.com/yoga.jpg",
          meeting_days: ["Tuesday", "Thursday"],
          meeting_start_time: ~T[10:00:00],
          meeting_end_time: ~T[11:00:00],
          age_range: "5-10 years",
          location: "Berlin"
        )

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      assert has_element?(view, "h1", "Yoga for Kids")
      assert has_element?(view, "#program-cover-image")
      assert has_element?(view, "[phx-click='back_to_programs']")
    end

    test "renders title and schedule info with gradient fallback", %{conn: conn} do
      program =
        insert(:program_schema,
          title: "Chess Club",
          cover_image_url: nil,
          meeting_days: ["Wednesday"],
          meeting_start_time: ~T[14:00:00],
          meeting_end_time: ~T[15:30:00],
          age_range: "8-12 years",
          location: "Munich"
        )

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      assert has_element?(view, "h1", "Chess Club")
      refute has_element?(view, "#program-cover-image")
      assert has_element?(view, "#program-hero")
      assert has_element?(view, "[phx-click='back_to_programs']")
    end

    test "renders provider business name above the program title", %{conn: conn} do
      provider = provider_profile_fixture(business_name: "Starlight Coaching")
      program = insert(:program_schema, provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      assert has_element?(view, "#hero-business-name", "Starlight Coaching")
    end

    test "renders the subtitle below the program title", %{conn: conn} do
      provider = provider_profile_fixture()

      program =
        insert(:program_schema,
          provider_id: provider.id,
          title: "Chess Club",
          subtitle: "For beginners, no experience needed"
        )

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      assert has_element?(view, "#program-hero-headline-subtitle", "For beginners")
    end

    test "renders no subtitle element when the program has none", %{conn: conn} do
      provider = provider_profile_fixture()
      program = insert(:program_schema, provider_id: provider.id, subtitle: nil)

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      refute has_element?(view, "#program-hero-headline-subtitle")
    end

    test "omits business name when provider profile is draft", %{conn: conn} do
      provider =
        provider_profile_fixture(
          business_name: "Not Ready Yet",
          profile_status: "draft"
        )

      program = insert(:program_schema, provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      refute has_element?(view, "#hero-business-name")
    end
  end

  describe "staff member display" do
    test "program with staff shows team member names", %{conn: conn} do
      provider = provider_profile_fixture()

      program =
        insert(:program_schema, provider_id: provider.id, title: "Soccer Academy")

      staff =
        staff_member_fixture(
          provider_id: provider.id,
          first_name: "Coach",
          last_name: "Smith",
          role: "Head Coach"
        )

      insert(:program_staff_assignment_schema,
        provider_id: provider.id,
        program_id: program.id,
        staff_member_id: staff.id
      )

      {:ok, view, html} = live(conn, ~p"/programs/#{program.id}")

      assert has_element?(view, "#hero-card-staff-#{staff.id}")
      assert html =~ "Coach Smith"
      assert html =~ "Head Coach"
      assert has_element?(view, "h3", "Meet the Hero")
    end

    test "program with multiple staff shows plural heading", %{conn: conn} do
      provider = provider_profile_fixture()

      program =
        insert(:program_schema, provider_id: provider.id, title: "STEM Camp")

      alice =
        staff_member_fixture(
          provider_id: provider.id,
          first_name: "Alice",
          last_name: "Johnson",
          role: "Instructor"
        )

      bob =
        staff_member_fixture(
          provider_id: provider.id,
          first_name: "Bob",
          last_name: "Williams",
          role: "Assistant Instructor"
        )

      for staff <- [alice, bob] do
        insert(:program_staff_assignment_schema,
          provider_id: provider.id,
          program_id: program.id,
          staff_member_id: staff.id
        )
      end

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      assert has_element?(view, "h3", "Meet the Heroes")
    end

    test "lead-flagged assignment (only staff) renders Lead Instructor card",
         %{conn: conn} do
      provider = provider_profile_fixture()

      instructor =
        staff_member_fixture(
          provider_id: provider.id,
          first_name: "Dr.",
          last_name: "Strange"
        )

      program =
        insert(:program_schema, provider_id: provider.id, title: "Music for Kids")

      insert(:program_staff_assignment_schema,
        provider_id: provider.id,
        program_id: program.id,
        staff_member_id: instructor.id,
        is_lead_instructor: true
      )

      {:ok, view, html} = live(conn, ~p"/programs/#{program.id}")

      assert has_element?(view, "#hero-card-staff-#{instructor.id}")
      assert html =~ "Dr. Strange"
      assert html =~ "Lead Instructor"
      assert has_element?(view, "h3", "Meet the Hero")
    end

    test "renders the lead card before other staff, regardless of assignment order",
         %{conn: conn} do
      provider = provider_profile_fixture()

      lead =
        staff_member_fixture(provider_id: provider.id, first_name: "Marie", last_name: "Curie")

      assistant =
        staff_member_fixture(
          provider_id: provider.id,
          first_name: "Coach",
          last_name: "Smith",
          role: "Assistant"
        )

      program =
        insert(:program_schema, provider_id: provider.id, title: "Combined Camp")

      # Assign the assistant first (earlier assigned_at) to prove ordering is
      # lead-first, not assignment order.
      insert(:program_staff_assignment_schema,
        provider_id: provider.id,
        program_id: program.id,
        staff_member_id: assistant.id
      )

      insert(:program_staff_assignment_schema,
        provider_id: provider.id,
        program_id: program.id,
        staff_member_id: lead.id,
        is_lead_instructor: true
      )

      {:ok, view, html} = live(conn, ~p"/programs/#{program.id}")

      assert has_element?(view, "#hero-card-staff-#{lead.id}")
      assert has_element?(view, "#hero-card-staff-#{assistant.id}")

      lead_pos = :binary.match(html, "hero-card-staff-#{lead.id}") |> elem(0)
      assistant_pos = :binary.match(html, "hero-card-staff-#{assistant.id}") |> elem(0)

      assert lead_pos < assistant_pos,
             "expected lead card to render before other staff; got lead at #{lead_pos}, assistant at #{assistant_pos}"
    end

    test "lead instructor card shows the staff member's rich fields with the badge",
         %{conn: conn} do
      provider = provider_profile_fixture()

      lead =
        staff_member_fixture(
          provider_id: provider.id,
          first_name: "Alice",
          last_name: "Lead",
          role: "Head Coach",
          bio: "10 years experience"
        )

      program = insert(:program_schema, provider_id: provider.id)

      insert(:program_staff_assignment_schema,
        provider_id: provider.id,
        program_id: program.id,
        staff_member_id: lead.id,
        is_lead_instructor: true
      )

      {:ok, view, html} = live(conn, ~p"/programs/#{program.id}")

      assert has_element?(view, "#hero-card-staff-#{lead.id}")
      assert html =~ "Head Coach"
      assert html =~ "10 years experience"
      assert html =~ "Lead Instructor"
      assert has_element?(view, "h3", "Meet the Hero")
    end

    test "program without instructor or staff hides hero section", %{conn: conn} do
      program = insert(:program_schema, title: "Art Class")
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      # Trigger: no staff members for this provider (provider_id is nil)
      # Why: instructor section only renders when real team members exist
      # Outcome: neither "Meet the Heroes" nor "Meet the Hero" heading is shown
      refute has_element?(view, "h3", "Meet the Hero")
      refute has_element?(view, "h3", "Meet the Heroes")
    end

    test "staff email is not shown on public page", %{conn: conn} do
      provider = provider_profile_fixture()
      program = insert(:program_schema, provider_id: provider.id)

      staff =
        staff_member_fixture(
          provider_id: provider.id,
          first_name: "Jane",
          last_name: "Doe",
          email: "jane.secret@example.com"
        )

      insert(:program_staff_assignment_schema,
        provider_id: provider.id,
        program_id: program.id,
        staff_member_id: staff.id
      )

      {:ok, _view, html} = live(conn, ~p"/programs/#{program.id}")

      assert html =~ "Jane Doe"
      refute html =~ "jane.secret@example.com"
    end

    test "shows only staff assigned to the program, not other provider staff", %{conn: conn} do
      provider = provider_profile_fixture()
      program = insert(:program_schema, provider_id: provider.id)

      assigned =
        staff_member_fixture(
          provider_id: provider.id,
          first_name: "Assigned",
          last_name: "Coach"
        )

      staff_member_fixture(
        provider_id: provider.id,
        first_name: "Unassigned",
        last_name: "Bystander"
      )

      insert(:program_staff_assignment_schema,
        provider_id: provider.id,
        program_id: program.id,
        staff_member_id: assigned.id
      )

      {:ok, _view, html} = live(conn, ~p"/programs/#{program.id}")

      assert html =~ "Assigned Coach"
      refute html =~ "Unassigned Bystander"
    end
  end

  describe "provider profile card" do
    test "renders business name and description for an active provider", %{conn: conn} do
      provider =
        provider_profile_fixture(
          business_name: "Starlight Coaching",
          description: "Empowering kids through play-based learning."
        )

      program = insert(:program_schema, provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      assert has_element?(view, "#provider-profile-card h4", "Starlight Coaching")
      assert render(view) =~ "Empowering kids through play-based learning."
    end

    test "renders logo image when logo_url is present", %{conn: conn} do
      provider =
        provider_profile_fixture(
          business_name: "Starlight Coaching",
          logo_url: "https://cdn.example.com/starlight.png"
        )

      program = insert(:program_schema, provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      assert has_element?(
               view,
               "#provider-profile-card img[src='https://cdn.example.com/starlight.png']"
             )
    end

    test "renders initials avatar when logo_url is missing", %{conn: conn} do
      provider = provider_profile_fixture(business_name: "Tiger Academy", logo_url: nil)
      program = insert(:program_schema, provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      refute has_element?(view, "#provider-profile-card img")
      assert has_element?(view, "#provider-profile-card", "TA")
    end

    test "does not render the card when the provider is in draft status", %{conn: conn} do
      provider =
        provider_profile_fixture(
          business_name: "Not Ready Yet",
          profile_status: "draft"
        )

      program = insert(:program_schema, provider_id: provider.id)

      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      refute has_element?(view, "#provider-profile-card")
    end
  end

  describe "pricing display" do
    test "renders formatted program price", %{conn: conn} do
      program = insert(:program_schema, price: Decimal.new("149.99"))
      {:ok, _view, html} = live(conn, ~p"/programs/#{program.id}")

      assert html =~ "€149.99"
    end

    test "bottom CTA includes price in button label", %{conn: conn} do
      program = insert(:program_schema, price: Decimal.new("149.99"))
      {:ok, view, _html} = live(conn, ~p"/programs/#{program.id}")

      assert has_element?(view, "#enroll-bottom-cta", "Enroll Now - €149.99")
    end
  end
end
