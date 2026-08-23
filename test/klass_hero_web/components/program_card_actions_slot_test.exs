defmodule KlassHeroWeb.ProgramCardActionsSlotTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias KlassHeroWeb.ProgramComponents

  @base_program %{
    id: "test-slot-123",
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

  describe "program_card :actions slot" do
    test "renders the slot content when provided" do
      assigns = %{program: @base_program}

      html =
        rendered_to_string(~H"""
        <ProgramComponents.program_card program={@program}>
          <:actions>
            <button id="slot-action-button">Do Something</button>
          </:actions>
        </ProgramComponents.program_card>
        """)

      doc = LazyHTML.from_fragment(html)
      assert Enum.count(LazyHTML.query(doc, "button#slot-action-button")) == 1
      assert LazyHTML.text(LazyHTML.query(doc, "button#slot-action-button")) =~ "Do Something"
    end

    test "renders no action container when slot is empty" do
      html = render_component(&ProgramComponents.program_card/1, program: @base_program)
      doc = LazyHTML.from_fragment(html)

      refute html =~ "slot-action-button"
      assert Enum.empty?(LazyHTML.query(doc, "button#slot-action-button"))
      refute doc |> LazyHTML.query(".px-6.pb-6") |> Enum.any?()
    end
  end
end
