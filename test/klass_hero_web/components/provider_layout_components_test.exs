defmodule KlassHeroWeb.ProviderLayoutComponentsTest do
  @moduledoc """
  Phase 3 — `Pv*` provider-surface components.

  Asserts each component renders the bundle's structural contract: black
  sidebar with yellow active accent, topbar with verified pill, stat-card
  trend arrow, roster check-in toggle, request card footer actions.
  """

  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias KlassHeroWeb.ProviderLayoutComponents

  describe "pv_sidebar/1" do
    test "marks the active nav item with aria-current=page", %{} do
      html = render_pv_sidebar(active: :home)

      assert html =~ ~s|aria-current="page"|
      assert html =~ "Overview"
      assert html =~ "Sessions"
      assert html =~ "Comms"
    end

    test "uses black surface with yellow active accent on desktop", %{} do
      html = render_pv_sidebar(active: :home)

      # Black sidebar surface
      assert html =~ "bg-black"
      # Yellow active item
      assert html =~ "bg-hero-yellow-500"
    end

    test "renders the mobile bottom-tab nav (black surface)", %{} do
      html = render_pv_sidebar(active: :messages)

      assert html =~ ~s|aria-label="Provider bottom navigation"|
      assert html =~ "fixed bottom-0"
    end

    test "renders 'Coming soon' tooltip for items without an href", %{} do
      html = render_pv_sidebar(active: :home)

      assert html =~ "Schedule"
      assert html =~ ~s|title="Coming soon"|
    end
  end

  describe "pv_topbar/1" do
    test "renders provider name and verified pill on desktop", %{} do
      html =
        render_pv_topbar(provider: %{name: "CodeKids Berlin", tagline: "Tech for kids", verified?: true})

      assert html =~ "CodeKids Berlin"
      assert html =~ "Verified"
      assert html =~ "Tech for kids"
    end

    test "omits the verified pill when provider isn't verified", %{} do
      html = render_pv_topbar(provider: %{name: "Newbie LLC", verified?: false})

      assert html =~ "Newbie LLC"
      refute html =~ "Verified"
    end

    test "renders the New program CTA when show_new_program_cta is true", %{} do
      html =
        render_pv_topbar(
          provider: %{name: "X", verified?: true},
          show_new_program_cta: true
        )

      assert html =~ "New program"
    end

    test "emits no <h1> — the page title owns the single document heading", %{} do
      # Both desktop + mobile variants render in the same DOM, so the topbar
      # must not contribute any <h1>; each provider page's LiveView supplies it.
      html = render_pv_topbar(provider: %{name: "CodeKids Berlin", verified?: true})

      refute html =~ "<h1"
      # Provider name still renders (just not as a heading).
      assert html =~ "CodeKids Berlin"
    end
  end

  describe "pv_stat_card/1" do
    test "renders title, value, and an icon chip", %{} do
      html =
        render_component(&ProviderLayoutComponents.pv_stat_card/1, %{
          title: "Active programs",
          value: "12",
          icon: "hero-academic-cap",
          tone: :primary
        })

      assert html =~ "Active programs"
      assert html =~ ">12<"
      assert html =~ "hero-academic-cap"
    end

    test "renders an upward trend arrow when trend > 0", %{} do
      html =
        render_component(&ProviderLayoutComponents.pv_stat_card/1, %{
          title: "Bookings",
          value: "47",
          icon: "hero-currency-euro",
          trend: 12
        })

      assert html =~ "↑"
      assert html =~ "12%"
      assert html =~ "text-emerald-600"
    end

    test "renders a downward trend arrow when trend < 0", %{} do
      html =
        render_component(&ProviderLayoutComponents.pv_stat_card/1, %{
          title: "Cancellations",
          value: "3",
          icon: "hero-x-mark",
          trend: -5
        })

      assert html =~ "↓"
      assert html =~ "5%"
      assert html =~ "text-red-500"
    end

    test "hides trend arrow when trend is nil", %{} do
      html =
        render_component(&ProviderLayoutComponents.pv_stat_card/1, %{
          title: "Revenue",
          value: "—",
          icon: "hero-currency-euro",
          tone: :cool
        })

      refute html =~ "↑"
      refute html =~ "↓"
    end
  end

  describe "pv_earnings_chart/1" do
    test "renders the explainer when data is empty", %{} do
      html = render_component(&ProviderLayoutComponents.pv_earnings_chart/1, %{data: []})

      assert html =~ "Earnings trend"
      assert html =~ "coming soon"
    end

    test "renders bars when data has rows", %{} do
      data = [%{w: "W1", v: 100}, %{w: "W2", v: 200}]
      html = render_component(&ProviderLayoutComponents.pv_earnings_chart/1, %{data: data})

      assert html =~ "W1"
      assert html =~ "W2"
      # Tallest bar should be 100% height; W1 should be 50%.
      assert html =~ "height: 50%"
      assert html =~ "height: 100%"
    end
  end

  describe "pv_program_row/1" do
    test "renders title, status pill, and edit button", %{} do
      program = %{
        id: "abc",
        title: "Football Stars",
        status: :live
      }

      html = render_component(&ProviderLayoutComponents.pv_program_row/1, %{program: program})

      assert html =~ "Football Stars"
      assert html =~ "live"
      assert html =~ ~s|aria-label="Edit program"|
      assert html =~ ~s|phx-value-program-id="abc"|
    end

    test "renders the cover as an object-cover img when cover_image_url is set", %{} do
      html = render_program_row(cover_image_url: "https://example.com/cover.jpg")
      doc = LazyHTML.from_fragment(html)

      img = LazyHTML.query(doc, "img#pv-program-cover-abc")

      assert Enum.count(img) == 1
      assert LazyHTML.attribute(img, "src") == ["https://example.com/cover.jpg"]
      assert LazyHTML.attribute(img, "loading") == ["lazy"]
      assert LazyHTML.attribute(img, "alt") == ["Football Stars"]

      # object-cover is what keeps the thumbnail from rendering a top-left crop
      # at natural size — the bug in #1072.
      assert hd(LazyHTML.attribute(img, "class")) =~ "object-cover"
    end

    test "renders the gradient fallback and no img when cover_image_url is nil", %{} do
      html = render_program_row(cover_image_url: nil)
      doc = LazyHTML.from_fragment(html)

      assert Enum.empty?(LazyHTML.query(doc, "img#pv-program-cover-abc"))
      assert html =~ "linear-gradient"
    end
  end

  describe "pv_roster/1" do
    test "renders the empty state when kids is []", %{} do
      html =
        render_component(&ProviderLayoutComponents.pv_roster/1, %{
          session: %{subtitle: "Code Camp · 15:30 – 17:00"},
          kids: []
        })

      # Phoenix HTML-escapes the apostrophe in the heading.
      assert html =~ "Today&#39;s check-ins"
      assert html =~ "No registered children"
    end

    test "renders one row per kid + check-in toggle reflects present?", %{} do
      kids = [
        %{id: "a", name: "Mila", parent: "Anna K.", present?: true, color: "#FFEAC9"},
        %{id: "b", name: "Theo", parent: "Markus L.", present?: false, color: "#33CFFF"}
      ]

      html =
        render_component(&ProviderLayoutComponents.pv_roster/1, %{
          session: %{subtitle: "Code Camp"},
          kids: kids
        })

      assert html =~ "Mila"
      assert html =~ "Theo"
      assert html =~ "Anna K."
      assert html =~ ~s|aria-label="Mark absent"|
      assert html =~ ~s|aria-label="Mark present"|
    end
  end

  ## ------------------------------------------------------------------ helpers

  defp render_program_row(overrides) do
    program = Enum.into(overrides, %{id: "abc", title: "Football Stars", status: :live})

    render_component(&ProviderLayoutComponents.pv_program_row/1, %{program: program})
  end

  defp render_pv_sidebar(opts) do
    assigns = %{active: Keyword.fetch!(opts, :active)}

    rendered_to_string(~H"""
    <ProviderLayoutComponents.pv_sidebar active={@active} />
    """)
  end

  defp render_pv_topbar(opts) do
    assigns = %{
      provider: Keyword.fetch!(opts, :provider),
      show_new_program_cta: Keyword.get(opts, :show_new_program_cta, false),
      user: Keyword.get(opts, :user, %{name: "Test Provider", email: "provider@example.com"})
    }

    rendered_to_string(~H"""
    <ProviderLayoutComponents.pv_topbar
      provider={@provider}
      show_new_program_cta={@show_new_program_cta}
      user={@user}
    />
    """)
  end
end
