defmodule KlassHeroWeb.BookingComponents do
  @moduledoc """
  Provides booking and enrollment-specific components for Klass Hero application.

  This module contains domain-specific components related to the booking process,
  payment information, and enrollment confirmations.
  """
  use Phoenix.Component
  use Gettext, backend: KlassHeroWeb.Gettext

  import KlassHeroWeb.UIComponents

  alias KlassHeroWeb.Theme

  @doc """
  Renders an informational box with color variants.

  Supports multiple variants for different message types:
  - `:info` - Blue background for informational content (default)
  - `:neutral` - Gray background for general information
  - `:success` - Green background for success messages
  - `:warning` - Yellow background for warnings
  - `:error` - Red background for errors

  ## Examples

      <.info_box variant={:info} title="Bank Transfer Details">
        <p>Transfer details and instructions...</p>
      </.info_box>

      <.info_box variant={:neutral} icon="📧" title="Invoice Information">
        <ul>
          <li>Point 1</li>
          <li>Point 2</li>
        </ul>
      </.info_box>
  """
  attr :variant, :atom, default: :info, values: [:info, :neutral, :success, :warning, :error]
  attr :title, :string, required: true
  attr :icon, :string, default: nil
  attr :class, :string, default: ""
  slot :inner_block, required: true
  slot :footer, doc: "Optional footer content for additional notes or actions"

  def info_box(assigns) do
    ~H"""
    <div class={[
      "p-6 shadow-lg",
      Theme.rounded(:xl),
      info_box_styles(@variant),
      @class
    ]}>
      <div class="flex items-start gap-3">
        <div :if={@icon} class="text-2xl">{@icon}</div>
        <div class="flex-1">
          <h3 :if={@title} class={[Theme.typography(:card_title), "text-hero-black mb-4"]}>
            {@title}
          </h3>
          <div class="text-hero-black-100">
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>
      <div
        :if={@footer != []}
        class={[
          "mt-4 pt-4",
          info_box_footer_border(@variant)
        ]}
      >
        {render_slot(@footer)}
      </div>
    </div>
    """
  end

  defp info_box_styles(:info), do: "bg-hero-blue-50 border-2 border-hero-blue-200"
  defp info_box_styles(:neutral), do: "bg-hero-grey-50 border border-hero-grey-200"
  defp info_box_styles(:success), do: "bg-green-50 border-2 border-green-200"
  defp info_box_styles(:warning), do: "bg-hero-yellow-50 border-2 border-hero-yellow-200"
  defp info_box_styles(:error), do: "bg-red-50 border-2 border-red-200"

  defp info_box_footer_border(:info), do: "border-t border-hero-blue-300"
  defp info_box_footer_border(:neutral), do: "border-t border-hero-grey-300"
  defp info_box_footer_border(:success), do: "border-t border-green-300"
  defp info_box_footer_border(:warning), do: "border-t border-hero-yellow-300"
  defp info_box_footer_border(:error), do: "border-t border-red-300"

  @doc """
  Renders a booking/payment summary card with line items and totals.

  Displays a structured summary of costs with support for:
  - Line items (label + value pairs)
  - Grand total with emphasis

  ## Examples

      <.booking_summary title="Payment Summary">
        <:line_item label="Program fee:" value="€45.00" />
        <:total label="Total due today" value="€45.00" />
      </.booking_summary>
  """
  attr :title, :string, default: "Summary"
  attr :class, :string, default: ""

  slot :line_item, doc: "Regular line item with label and value" do
    attr :label, :string, required: true
    attr :value, :string, required: true
  end

  slot :total, doc: "Total line with emphasis" do
    attr :label, :string, required: true
    attr :value, :string, required: true
  end

  def booking_summary(assigns) do
    ~H"""
    <div class={["bg-white p-6 shadow-lg", Theme.rounded(:xl), @class]}>
      <h3 class={[Theme.typography(:card_title), "text-hero-black mb-4"]}>{@title}</h3>
      <div class="space-y-2">
        <div
          :for={item <- @line_item}
          class="flex justify-between text-hero-black-100"
        >
          <span>{item[:label]}</span>
          <span>{item[:value]}</span>
        </div>

        <!-- Total with emphasis -->
        <div
          :for={total <- @total}
          class={[
            "flex justify-between pt-2 border-t border-hero-grey-300",
            Theme.typography(:card_title)
          ]}
        >
          <span>{total[:label]}</span>
          <span class={Theme.text_color(:primary)}>{total[:value]}</span>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders eligibility feedback after a child is selected in the booking flow.

  Shows a green confirmation when the child is eligible, or a red warning with
  specific reasons when the child does not meet program requirements.

  ## Attributes

    * `status` - Eligibility state: `nil` (no child selected), `:eligible`, or
      `{:ineligible, [String.t()]}` with human-readable reasons.

  ## Examples

      <.eligibility_status status={:eligible} />
      <.eligibility_status status={{:ineligible, ["Child must be at least 6 years old"]}} />
  """
  attr :status, :any, required: true

  def eligibility_status(assigns) do
    ~H"""
    <div
      :if={@status == :eligible}
      class="flex items-center gap-2 p-3 bg-green-50 border border-green-200 rounded-lg mt-3"
    >
      <.icon name="hero-check-circle-mini" class="w-5 h-5 text-green-600" />
      <span class="text-sm text-green-700">
        {gettext("Child meets all program requirements")}
      </span>
    </div>
    <div
      :if={match?({:ineligible, _}, @status)}
      class="p-3 bg-red-50 border border-red-200 rounded-lg mt-3"
    >
      <div class="flex items-center gap-2 mb-2">
        <.icon name="hero-exclamation-triangle-mini" class="w-5 h-5 text-red-600" />
        <span class="text-sm font-semibold text-red-700">
          {gettext("Child does not meet program requirements")}
        </span>
      </div>
      <ul class="list-disc list-inside text-sm text-red-600 space-y-1">
        <li :for={reason <- elem(@status, 1)}>{reason}</li>
      </ul>
    </div>
    """
  end
end
