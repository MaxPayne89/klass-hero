defmodule KlassHeroWeb.ProviderHeroTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHeroWeb.CompositeComponents

  @provider_id "11111111-2222-3333-4444-555555555555"

  @filled %{
    id: @provider_id,
    business_name: "Starlight Coaching",
    initials: "SC",
    description: "Empowering kids through play-based learning.",
    logo_url: "https://cdn.example.com/logo.png",
    tagline: "Move. Play. Grow.",
    cover_image_url: "https://cdn.example.com/cover.png",
    social_links: [
      {:instagram, "Instagram", "https://instagram.com/starlight"},
      {:youtube, "YouTube", "https://youtube.com/@starlight"}
    ],
    trust_state: :verified
  }

  # The realistic state today: a provider who has filled in none of #1302's fields.
  @bare %{business_name: "Starlight Coaching", initials: "SC"}

  defp render_hero(provider, opts \\ []) do
    assigns = %{provider: provider, variant: Keyword.get(opts, :variant, :compact)}

    render_component(&CompositeComponents.provider_hero/1, assigns)
  end

  describe "compact variant" do
    test "renders identity, tagline, description and the trust mark" do
      html = render_hero(@filled)

      assert html =~ "Starlight Coaching"
      assert html =~ "Move. Play. Grow."
      assert html =~ "Empowering kids through play-based learning."
      assert html =~ ~s(data-trust-state="verified")
      assert html =~ ~s(data-variant="compact")
    end

    test "keeps the id the program detail page and its tests target" do
      assert render_hero(@filled) =~ ~s(id="provider-profile-card")
    end

    test "links the business name to the provider's public page" do
      assert render_hero(@filled) =~ ~s(href="/providers/#{@provider_id}")
    end

    test "renders the name as plain text when the map carries no id" do
      # A hand-built map from a preview or a test must not crash the page (#1073).
      html = render_hero(@bare)

      assert html =~ "Starlight Coaching"
      refute html =~ "/providers/"
    end

    test "renders the logo when present, initials when not" do
      assert render_hero(@filled) =~ "https://cdn.example.com/logo.png"

      bare = render_hero(@bare)
      refute bare =~ "<img"
      assert bare =~ "SC"
    end
  end

  describe "full variant" do
    test "renders the cover image as the background band" do
      html = render_hero(@filled, variant: :full)

      assert html =~ "https://cdn.example.com/cover.png"
      assert html =~ ~s(data-band="cover")
      refute html =~ ~s(data-band="gradient")
      assert html =~ ~s(data-variant="full")
    end

    test "falls back to a gradient band when there is no cover" do
      html = render_hero(@bare, variant: :full)

      # data-band, not a bare "gradient" match: the avatar fallback carries the
      # same gradient class, so a looser assertion would pass with no band at all.
      assert html =~ ~s(data-band="gradient")
      refute html =~ ~s(data-band="cover")
    end

    test "keeps the scrim that bounds contrast over an arbitrary cover" do
      assert render_hero(@filled, variant: :full) =~ "bg-white/90"
    end

    test "uses the on-light token for the tagline, not the plain muted one" do
      # Measured over a black cover behind the bg-white/90 scrim:
      #   hero-grey-600 (:secondary)      2.92:1  fails
      #   hero-grey-700 (:secondary_dark) 4.40:1  fails
      #   hero-grey-800 (--fg-muted-on-light) 6.77:1  passes
      # Only the third clears AA, so this token is not interchangeable with the
      # ones the rest of the component uses.
      html = render_hero(@filled, variant: :full)

      assert html =~ "text-[var(--fg-muted-on-light)]"
      refute html =~ "text-hero-grey-600"
    end

    test "omits the description, which belongs to the About section" do
      refute render_hero(@filled, variant: :full) =~
               "Empowering kids through play-based learning."
    end

    test "does not link the name — this variant is the page it would link to" do
      refute render_hero(@filled, variant: :full) =~ "/providers/"
    end
  end

  describe "social links" do
    test "renders one accessible, safely-targeted link per filled network" do
      html = render_hero(@filled)

      assert html =~ "https://instagram.com/starlight"
      assert html =~ "https://youtube.com/@starlight"
      assert html =~ ~s(rel="noopener noreferrer")
      # The glyph is aria-hidden, so the link needs its own accessible name.
      assert html =~ "Starlight Coaching on Instagram"
    end

    test "renders no row at all when the provider filled in none" do
      refute render_hero(@bare) =~ ~s(rel="noopener noreferrer")
    end
  end

  describe "empty and partial states" do
    test "renders both variants for a provider with nothing filled in" do
      for variant <- [:compact, :full] do
        html = render_hero(@bare, variant: variant)

        assert html =~ "Starlight Coaching"
        # :unverified renders nothing rather than a negative badge.
        refute html =~ "data-trust-state"
      end
    end

    test "treats a blank string as absent, not as content" do
      blank = Map.merge(@bare, %{tagline: "   ", logo_url: "", cover_image_url: ""})

      html = render_hero(blank, variant: :full)

      refute html =~ "<img"
      assert html =~ "Starlight Coaching"
    end
  end
end
