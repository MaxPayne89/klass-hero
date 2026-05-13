defmodule KlassHeroWeb.ProgramComponentsHeroCardTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHeroWeb.ProgramComponents

  @full_attrs %{
    id: "hero-card-staff-abc123",
    name: "Ada Lovelace",
    initials: "AL",
    headshot_url: "https://example.com/ada.jpg",
    role: "Mathematics Lead",
    bio: "Pioneer of analytical engines.",
    tags: ["math", "science"],
    qualifications: ["MSc Computer Science", "First-Aid Certified"],
    badge: "Lead Instructor"
  }

  describe "hero_card/1" do
    test "renders full shape with every optional field populated" do
      html = render_component(&ProgramComponents.hero_card/1, @full_attrs)
      doc = LazyHTML.from_fragment(html)

      assert Enum.any?(LazyHTML.query(doc, "#hero-card-staff-abc123"))

      assert html =~ "Ada Lovelace"
      assert html =~ "Mathematics Lead"
      assert html =~ "Pioneer of analytical engines."
      assert html =~ "Lead Instructor"

      img = LazyHTML.query(doc, "img[src=\"https://example.com/ada.jpg\"]")
      assert Enum.any?(img), "expected an <img> with the headshot src"

      assert html =~ "math"
      assert html =~ "science"
      assert html =~ "MSc Computer Science"
      assert html =~ "First-Aid Certified"
    end

    test "renders sparse shape with only required fields" do
      attrs = %{id: "hero-card-instructor-xyz", name: "Dr. Strange", initials: "DS"}

      html = render_component(&ProgramComponents.hero_card/1, attrs)
      doc = LazyHTML.from_fragment(html)

      assert Enum.any?(LazyHTML.query(doc, "#hero-card-instructor-xyz"))
      assert html =~ "Dr. Strange"
      assert html =~ "DS"

      refute Enum.any?(LazyHTML.query(doc, "img")), "no headshot → no <img> element"

      refute html =~ "Mathematics Lead"
      refute html =~ "Pioneer of analytical engines."
      refute html =~ "Lead Instructor"
    end

    test "renders badge text when :badge attr is set" do
      attrs = Map.put(@full_attrs, :badge, "Lead Instructor")
      html = render_component(&ProgramComponents.hero_card/1, attrs)

      assert html =~ "Lead Instructor"
    end

    test "omits badge text when :badge attr is nil" do
      attrs = Map.put(@full_attrs, :badge, nil)
      html = render_component(&ProgramComponents.hero_card/1, attrs)

      refute html =~ "Lead Instructor"
    end
  end
end
