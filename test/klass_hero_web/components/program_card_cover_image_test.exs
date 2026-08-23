defmodule KlassHeroWeb.ProgramCardCoverImageTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHeroWeb.ProgramComponents

  @base_program %{
    id: "test-123",
    title: "Art Adventures",
    description: "Explore creativity",
    category: "Arts",
    meeting_days: ["Monday"],
    meeting_start_time: ~T[15:00:00],
    meeting_end_time: ~T[17:00:00],
    age_range: "6-8 years",
    price: Decimal.new("120.00"),
    period: "per month",
    spots_left: nil,
    gradient_class: "bg-gradient-to-br from-hero-blue-400 to-hero-blue-600",
    icon_name: "hero-paint-brush",
    cover_image_url: nil,
    is_online: false
  }

  describe "program_card cover image" do
    test "renders cover image when cover_image_url is present" do
      program = Map.put(@base_program, :cover_image_url, "https://example.com/cover.jpg")
      html = render_component(&ProgramComponents.program_card/1, program: program)
      doc = LazyHTML.from_fragment(html)

      imgs = LazyHTML.query(doc, "img[src='https://example.com/cover.jpg']")
      assert Enum.count(imgs) == 1
      assert LazyHTML.attribute(imgs, "loading") == ["lazy"]
      assert LazyHTML.attribute(imgs, "id") == ["program-cover-test-123"]

      # Icon should NOT be rendered when cover image is present
      assert Enum.empty?(LazyHTML.query(doc, ".hero-paint-brush"))
    end

    test "renders gradient fallback when cover_image_url is nil" do
      html = render_component(&ProgramComponents.program_card/1, program: @base_program)
      doc = LazyHTML.from_fragment(html)

      assert Enum.empty?(LazyHTML.query(doc, "img[id='program-cover-test-123']"))
      refute Enum.empty?(LazyHTML.query(doc, ".bg-gradient-to-br"))
    end
  end

  describe "card header badges" do
    test "renders category badge with cover image" do
      program = Map.put(@base_program, :cover_image_url, "https://example.com/cover.jpg")
      html = render_component(&ProgramComponents.program_card/1, program: program)
      doc = LazyHTML.from_fragment(html)

      assert LazyHTML.text(doc) =~ "Arts"
    end

    test "renders category badge with gradient fallback" do
      html = render_component(&ProgramComponents.program_card/1, program: @base_program)
      doc = LazyHTML.from_fragment(html)

      assert LazyHTML.text(doc) =~ "Arts"
    end

    test "renders ONLINE badge when is_online is true with cover image" do
      program =
        @base_program
        |> Map.put(:cover_image_url, "https://example.com/cover.jpg")
        |> Map.put(:is_online, true)

      html = render_component(&ProgramComponents.program_card/1, program: program)
      doc = LazyHTML.from_fragment(html)

      assert LazyHTML.text(doc) =~ "ONLINE"
    end

    test "renders ONLINE badge when is_online is true with gradient fallback" do
      program = Map.put(@base_program, :is_online, true)
      html = render_component(&ProgramComponents.program_card/1, program: program)
      doc = LazyHTML.from_fragment(html)

      assert LazyHTML.text(doc) =~ "ONLINE"
    end

    test "does not render ONLINE badge when is_online is false" do
      html = render_component(&ProgramComponents.program_card/1, program: @base_program)
      doc = LazyHTML.from_fragment(html)

      refute LazyHTML.text(doc) =~ "ONLINE"
    end

    test "renders spots badge when spots_left <= 5 with cover image" do
      program =
        @base_program
        |> Map.put(:cover_image_url, "https://example.com/cover.jpg")
        |> Map.put(:spots_left, 3)

      html = render_component(&ProgramComponents.program_card/1, program: program)
      doc = LazyHTML.from_fragment(html)

      assert LazyHTML.text(doc) =~ "3 spots left!"
    end

    test "renders spots badge when spots_left <= 5 with gradient fallback" do
      program = Map.put(@base_program, :spots_left, 3)
      html = render_component(&ProgramComponents.program_card/1, program: program)
      doc = LazyHTML.from_fragment(html)

      assert LazyHTML.text(doc) =~ "3 spots left!"
    end
  end
end
