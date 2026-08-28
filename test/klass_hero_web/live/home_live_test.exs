defmodule KlassHeroWeb.HomeLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  describe "home page" do
    test "renders hero section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "h1", "Trusted Heroes")
      assert has_element?(view, "h1", "for Our Youth")
    end

    test "renders sections in the design-handoff Mk* order", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # Bundle order (design_handoff/marketing/Sections.jsx): Hero → Featured →
      # Features (Why Klass Hero) → Provider CTA → Founder → FAQ. Pricing is
      # intentionally skipped — gated on transactions (#178).
      ids_in_order = [
        ~s|id="mk-hero"|,
        ~s|id="mk-featured"|,
        ~s|id="mk-features"|,
        ~s|id="mk-provider-cta"|,
        ~s|id="mk-founder"|,
        ~s|id="mk-faq"|
      ]

      positions =
        Enum.map(ids_in_order, fn marker ->
          assert html =~ marker, "expected #{marker} to render"
          html |> String.split(marker) |> hd() |> String.length()
        end)

      assert positions == Enum.sort(positions),
             "section ids appeared out of order: #{inspect(Enum.zip(ids_in_order, positions))}"

      refute html =~ ~s|id="pricing-section"|,
             "pricing section is hidden until #178 lands; remove the HEEx comment in home_live.ex when re-enabling"
    end

    test "renders search bar in hero section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "input[placeholder='Search: coding, football, art...']")
      assert has_element?(view, "button", "Find Programs")
    end

    test "renders trending tags", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "span", "Trending in Berlin:")
      assert has_element?(view, "button", "Swimming")
      assert has_element?(view, "button", "Math Tutor")
      assert has_element?(view, "button", "Summer Camp")
      assert has_element?(view, "button", "Piano")
      assert has_element?(view, "button", "Soccer")
    end

    test "search form submission navigates to programs page with query", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> form("#home-search-form", %{search: "piano lessons"})
      |> render_submit()

      assert_redirect(view, "/programs?q=piano+lessons")
    end

    test "empty search does not navigate", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> form("#home-search-form", %{search: "  "})
      |> render_submit()

      refute_redirected(view, "/programs")
    end

    test "clicking trending tag navigates to programs page with tag query", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("button[phx-value-tag='Swimming']")
      |> render_click()

      assert_redirect(view, "/programs?q=Swimming")
    end

    test "clicking different trending tag navigates correctly", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("button[phx-value-tag='Math Tutor']")
      |> render_click()

      assert_redirect(view, "/programs?q=Math+Tutor")
    end

    test "renders featured programs section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#mk-featured")
      assert has_element?(view, "h2", "Afterschool Adventures Await")
      assert has_element?(view, "#mk-featured-grid")
    end

    test "renders featured programs stream container", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Stream container has phx-update="stream" attribute
      assert has_element?(view, "#mk-featured-grid[phx-update='stream']")
    end

    test "renders view all programs link in featured section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # In the new design this is a navigate link, not a button.
      assert has_element?(view, "#mk-featured a[href='/programs']")
    end

    test "renders why klass hero section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#mk-features")
      assert has_element?(view, "h2", "Everything parents need, nothing they don't")
    end

    test "renders why klass hero feature cards", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "h3", "Safety First")
      assert has_element?(view, "h3", "Easy Scheduling")
      assert has_element?(view, "h3", "Community Focused")
    end

    test "renders provider CTA section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#mk-provider-cta")
      assert has_element?(view, "h2", "How to Grow Your Youth Program")
      assert has_element?(view, "#mk-provider-cta-subtitle", "Are you an educator, coach, or artist?")
      assert has_element?(view, "#mk-provider-cta-primary", "Learn How to Become a Hero")

      # Three numbered step cards.
      assert has_element?(view, "h4", "List Your Program")
      assert has_element?(view, "h4", "Get Bookings")
      assert has_element?(view, "h4", "Get Paid & Grow")
    end

    test "renders founder section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#mk-founder")
      assert has_element?(view, "h2", "Built by Parents to Empower Educators.")
      assert has_element?(view, "#mk-founder a[href='/about']")
    end

    test "renders faq section with all 9 questions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#mk-faq")

      # FAQ items render as native <details> with <summary> headers — verify
      # all 9 question strings appear inside summary elements.
      questions = [
        "How does the 6-step provider vetting process work?",
        "Can I list my programs on Klass Hero and what does it cost?",
        "How does the booking system work?",
        "Is Klass Hero free for parents to use?",
        "Do I need an account to book?",
        "Can I change my booking date?",
        "What if my child gets sick?",
        "Where is Klass Hero available?",
        "Can I buy a gift voucher?"
      ]

      for q <- questions do
        assert has_element?(view, "summary", q), "expected FAQ summary: #{q}"
      end
    end

    test "faq items have stable ids 1..9", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for n <- 1..9 do
        assert has_element?(view, "details#faq-#{n}"), "expected #faq-#{n} <details>"
      end
    end

    test "renders marketing header chrome", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Sticky horizontal nav rendered by mk_header in the marketing layout.
      assert has_element?(view, "header nav a", "Programs")
      assert has_element?(view, "header nav a", "For Providers")
      assert has_element?(view, "header nav a", "Trust & Safety")
      assert has_element?(view, "header nav a", "About")
      assert has_element?(view, "header nav a", "Contact")
    end

    test "renders marketing footer with legal links", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "footer a", "Privacy")
      assert has_element?(view, "footer a", "Terms")
    end

    test "renders a featured program's subtitle under its title", %{conn: conn} do
      insert(:program_schema,
        title: "Chess Club",
        subtitle: "For beginners, no experience needed",
        description: "Develop strategic thinking through chess",
        meeting_days: [],
        price: Decimal.new("60.00"),
        provider_id: insert(:provider_profile_schema).id
      )

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#mk-featured-grid", "For beginners, no experience needed")
    end

    test "clicking featured program card navigates to program detail", %{conn: conn} do
      %{id: program_id} =
        insert(:program_schema,
          title: "Featured Test Program",
          description: "A test program for featured display",
          meeting_days: [],
          provider_id: insert(:provider_profile_schema).id
        )

      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("[phx-click='view_program'][phx-value-program-id='#{program_id}']")
      |> render_click()

      assert_redirect(view, ~p"/programs/#{program_id}")
    end
  end
end
