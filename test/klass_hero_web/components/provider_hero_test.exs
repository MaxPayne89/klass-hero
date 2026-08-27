defmodule KlassHeroWeb.ProviderHeroTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHeroWeb.CompositeComponents
  alias KlassHeroWeb.Theme

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
    # data-band, not a bare "gradient" match: the avatar fallback carries the same
    # gradient class, so a looser assertion would pass with no band at all.
    test "paints exactly one band, chosen by whether a cover is set" do
      for {provider, present, absent} <- [
            {@filled, "cover", "gradient"},
            {@bare, "gradient", "cover"}
          ] do
        html = render_hero(provider, variant: :full)

        assert html =~ ~s(data-band="#{present}"),
               "expected a #{present} band for #{inspect(provider.business_name)}"

        refute html =~ ~s(data-band="#{absent}"),
               "expected no #{absent} band alongside the #{present} one"
      end
    end

    test "renders the cover image and keeps the variant marker" do
      html = render_hero(@filled, variant: :full)

      assert html =~ "https://cdn.example.com/cover.png"
      assert html =~ ~s(data-variant="full")
    end

    test "keeps every text node out of the band" do
      # This is what replaces the scrim. ContrastAudit only samples leaf elements
      # that carry text, so a band holding none is never measured against an
      # arbitrary upload — the cover can be shown at full contrast.
      band =
        @filled
        |> render_hero(variant: :full)
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[data-band]")
        |> LazyHTML.text()
        |> String.trim()

      assert band == "", "the cover band must carry no text, got: #{inspect(band)}"
    end

    test "drops the scrim, so the cover paints at full contrast" do
      refute render_hero(@filled, variant: :full) =~ "bg-white/90"
    end

    test "paints the identity card opaque" do
      # The precondition for dropping the scrim. ContrastAudit resolves a text
      # node's background by walking its ancestors, so an opaque card is what
      # stands between the reader and an arbitrary photo. A transparent one
      # would leave both the audit and the reader looking at the cover.
      card =
        @filled
        |> render_hero(variant: :full)
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(~s([data-testid="provider-identity-card"]))
        |> LazyHTML.attribute("class")

      assert [class] = card
      assert class =~ Theme.bg(:surface)
    end

    test "seats the avatar in the identity card, not in the band" do
      # What makes the medallion straddle the seam: the avatar is positioned
      # against the card, so the band keeps overflow-hidden for its own
      # rounding without clipping it.
      doc = @filled |> render_hero(variant: :full) |> LazyHTML.from_fragment()

      assert Enum.any?(LazyHTML.query(doc, ~s([data-testid="provider-identity-card"] img[src="#{@filled.logo_url}"])))
    end

    test "uses the on-light token for the tagline, not the plain muted one" do
      # The tagline sits on the opaque identity card now, not over a scrimmed
      # cover, so the old measurement behind bg-white/90 no longer describes it.
      # The token stays because :secondary and :secondary_dark both resolve to
      # --fg-muted, which the palette marks unsafe on the warm surfaces this
      # hero sits on; --fg-muted-on-light (hero-grey-800) is the one that holds
      # wherever the card is placed.
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
