defmodule KlassHeroWeb.Theme do
  @moduledoc """
  Centralized design tokens: gradients, colors, spacing, shadows, typography, rounded, transitions.

  ## Usage

      alias KlassHeroWeb.Theme

      <div class={Theme.gradient(:primary)}>...</div>
      <div class={Theme.bg(:primary)}>...</div>
      <span class={Theme.text_color(:heading)}>Title</span>

      {bg, text} = Theme.icon_styles(:primary)
      <span class={Theme.status(:available)}>Available</span>
  """

  @gradients %{
    primary: "bg-gradient-to-r from-hero-blue-500 to-hero-blue-600",
    hero: "bg-gradient-to-br from-hero-blue-400 via-hero-yellow-400 to-hero-yellow-500",
    comic: "bg-gradient-to-r from-hero-yellow-400 to-hero-blue-400",
    safety: "bg-gradient-to-r from-green-500 to-emerald-600",
    cool: "bg-gradient-to-r from-hero-blue-400 to-hero-blue-600",
    art: "bg-gradient-to-r from-hero-yellow-400 to-hero-pink-400",
    cream: "bg-hero-cream-100",
    base_fade: "bg-gradient-to-b from-hero-pink-50 to-white"
  }

  @doc """
  Returns the gradient class for the specified gradient name.

  ## Available Gradients

  - `:primary` - Hero blue horizontal gradient (hero-blue-500 to hero-blue-600)
  - `:hero` - Hero blue/yellow diagonal gradient
  - `:safety` - Green horizontal gradient (green-500 to emerald-600)
  - `:base_fade` - Vertical fade from the base pink surface (hero-pink-50) to white,
    for marketing sections that must meet a white/black seam on a clean edge

  ## Examples

      iex> Theme.gradient(:primary)
      "bg-gradient-to-r from-hero-blue-500 to-hero-blue-600"

      iex> Theme.gradient(:hero)
      "bg-gradient-to-br from-hero-blue-400 via-hero-yellow-400 to-hero-yellow-500"

      iex> Theme.gradient(:safety)
      "bg-gradient-to-r from-green-500 to-emerald-600"
  """
  def gradient(name) when is_atom(name) do
    Map.get(@gradients, name, @gradients.primary)
  end

  @doc "Returns all available gradient names."
  def available_gradients, do: Map.keys(@gradients)

  @doc "Returns a map of all gradients."
  def all_gradients, do: @gradients

  @colors %{
    primary: "hero-blue",
    secondary: "hero-grey",
    accent: "hero-yellow"
  }

  @doc """
  Returns the base color name for the specified color token.

  ## Examples

      iex> Theme.color(:primary)
      "hero-blue"
  """
  def color(:primary), do: @colors.primary
  def color(:secondary), do: @colors.secondary
  def color(:accent), do: @colors.accent

  @brand_colors %{
    primary: "hero-blue-600",
    primary_hover: "hero-blue-700",
    primary_light: "hero-blue-50",
    secondary: "hero-grey-500",
    secondary_hover: "hero-grey-600",
    accent: "hero-yellow-400",
    accent_hover: "hero-yellow-500",
    background: "hero-pink-50",
    background_light: "hero-pink-100",
    surface: "white",
    surface_light: "hero-pink-50",
    text_primary: "hero-black",
    text_secondary: "hero-black-100",
    text_muted: "hero-grey-500",
    border_light: "hero-grey-200",
    border_medium: "hero-grey-300",
    footer_bg: "hero-black",
    footer_text: "hero-grey-300"
  }

  @doc """
  Returns the brand color value for the given key.

  This map provides centralized brand color management for easy rebranding.
  All color values are Tailwind color names that can be used directly in classes.

  ## Available Colors

  ### Primary Colors
  - `:primary` - Main brand color (hero-blue-600)
  - `:primary_hover` - Hover state (hero-blue-700)
  - `:primary_light` - Light background (hero-blue-50)

  ### Accent Colors
  - `:accent` - Accent highlights (pink-500)
  - `:accent_hover` - Accent hover (pink-600)

  ### Surface Colors
  - `:surface` - Default background (white)
  - `:surface_light` - Light surface (slate-50)

  ### Text Colors
  - `:text_primary` - Primary text (slate-900)
  - `:text_secondary` - Secondary text (slate-700)
  - `:text_muted` - Muted text (slate-500)

  ### Border Colors
  - `:border_light` - Subtle borders (slate-200)
  - `:border_medium` - Medium borders (slate-300)

  ### Footer Colors
  - `:footer_bg` - Footer background (slate-900)
  - `:footer_text` - Footer text (slate-300)

  ## Examples

      iex> Theme.brand_color(:primary)
      "hero-blue-600"

      iex> Theme.brand_color(:accent)
      "pink-500"

      iex> Theme.brand_color(:text_primary)
      "slate-900"
  """
  def brand_color(key), do: Map.get(@brand_colors, key)

  @doc """
  Returns the background class for the specified variant.

  ## Variants

  - `:primary`, `:primary_light`, `:primary_dark` - Hero blue shades
  - `:secondary`, `:secondary_light`, `:secondary_dark` - Hero grey shades
  - `:accent`, `:accent_light` - Hero yellow shades
  - `:surface` - Default white background
  - `:muted` - Subtle gray background

  ## Examples

      iex> Theme.bg(:primary)
      "bg-hero-blue-600"

      iex> Theme.bg(:primary_light)
      "bg-hero-blue-50"
  """
  def bg(:primary), do: "bg-hero-blue-600"
  def bg(:primary_light), do: "bg-hero-blue-50"
  def bg(:primary_dark), do: "bg-hero-blue-700"
  def bg(:secondary), do: "bg-hero-grey-500"
  def bg(:secondary_light), do: "bg-hero-grey-50"
  def bg(:secondary_dark), do: "bg-hero-grey-700"
  def bg(:accent), do: "bg-hero-yellow-400"
  def bg(:accent_light), do: "bg-hero-yellow-100"
  def bg(:base), do: "bg-hero-pink-50"
  def bg(:surface), do: "bg-white"
  def bg(:muted), do: "bg-hero-grey-50"
  def bg(:light), do: "bg-hero-grey-100"
  def bg(:medium), do: "bg-hero-grey-200"

  @doc """
  Returns the text color class for the specified variant.

  ## Variants

  - `:primary`, `:primary_dark` - Hero blue text
  - `:secondary`, `:secondary_dark` - Hero grey text
  - `:accent` - Hero yellow text
  - `:heading` - Dark gray for headings
  - `:body` - Medium gray for body text
  - `:muted` - Light gray for secondary text
  - `:inverse` - White text for dark backgrounds

  ## Examples

      iex> Theme.text_color(:primary)
      "text-hero-blue-600"

      iex> Theme.text_color(:heading)
      "text-hero-black"
  """
  def text_color(:primary), do: "text-hero-blue-600"
  def text_color(:primary_dark), do: "text-hero-blue-700"
  def text_color(:secondary), do: "text-hero-grey-600"
  def text_color(:secondary_dark), do: "text-hero-grey-700"
  def text_color(:accent), do: "text-hero-yellow-400"
  def text_color(:accent_dark), do: "text-hero-yellow-600"
  def text_color(:heading), do: "text-hero-black"
  def text_color(:body), do: "text-hero-black-100"
  def text_color(:muted), do: "text-hero-grey-500"
  def text_color(:subtle), do: "text-hero-grey-400"
  def text_color(:inverse), do: "text-white"

  @doc """
  Returns the border color class for the specified variant.

  ## Examples

      iex> Theme.border_color(:primary)
      "border-hero-blue-500"

      iex> Theme.border_color(:light)
      "border-hero-grey-200"
  """
  def border_color(:primary), do: "border-hero-blue-500"
  def border_color(:primary_light), do: "border-hero-blue-200"
  def border_color(:secondary), do: "border-hero-grey-500"
  def border_color(:accent), do: "border-hero-yellow-400"
  def border_color(:light), do: "border-hero-grey-200"
  def border_color(:medium), do: "border-hero-grey-300"
  def border_color(:dark), do: "border-hero-grey-400"

  @doc """
  Returns a tuple of {background_class, text_class} for icon styling.

  ## Variants

  - `:primary`, `:secondary`, `:accent` - Brand colors
  - `:success`, `:warning`, `:danger`, `:info` - Status colors

  ## Examples

      {bg, text} = Theme.icon_styles(:primary)
      # bg = "bg-hero-blue-50"
      # text = "text-hero-blue-600"
  """
  def icon_styles(:primary), do: {"bg-hero-blue-50", "text-hero-blue-600"}
  def icon_styles(:secondary), do: {"bg-hero-grey-50", "text-hero-grey-500"}
  def icon_styles(:accent), do: {"bg-hero-yellow-100", "text-hero-yellow-600"}
  def icon_styles(:success), do: {"bg-green-100", "text-green-600"}
  def icon_styles(:warning), do: {"bg-hero-yellow-100", "text-hero-yellow-600"}
  def icon_styles(:danger), do: {"bg-red-100", "text-red-600"}
  def icon_styles(:info), do: {"bg-hero-blue-100", "text-hero-blue-600"}
  def icon_styles(:neutral), do: {"bg-gray-100", "text-gray-600"}

  @doc """
  Returns combined classes for status indicators (badges, pills, info boxes).

  Includes background, border, and text color in one string.

  ## Variants

  - `:available` - Green (positive/success state)
  - `:limited` - Yellow (warning state)
  - `:full` - Red (negative/danger state)
  - `:info` - Blue (informational)
  - `:neutral` - Gray (default/inactive)

  ## Examples

      iex> Theme.status(:available)
      "bg-green-50 border-green-200 text-green-700"
  """
  def status(:available), do: "bg-green-50 border-green-200 text-green-700"
  def status(:limited), do: "bg-yellow-50 border-yellow-200 text-yellow-700"
  def status(:full), do: "bg-red-50 border-red-200 text-red-700"
  def status(:info), do: "bg-blue-50 border-blue-200 text-blue-700"
  def status(:neutral), do: "bg-gray-50 border-gray-200 text-gray-700"

  @doc """
  Returns filled (borderless) badge classes for a status pill: a tinted `-100`
  background with `-800` text. The `-800` shade clears WCAG AA (≥4.5:1) on the
  `-100` tint, unlike the lighter `-700`/`-600` pairings that drift below it.

  Use for solid status badges (verification outcomes, document review). For the
  bordered, lighter pill use `status/1`.

  ## Examples

      iex> Theme.status_badge(:available)
      "bg-green-100 text-green-800"
  """
  def status_badge(:available), do: "bg-green-100 text-green-800"
  def status_badge(:limited), do: "bg-yellow-100 text-yellow-800"
  def status_badge(:full), do: "bg-red-100 text-red-800"
  def status_badge(:neutral), do: "bg-hero-grey-100 text-hero-grey-800"

  @doc """
  Returns width and height classes for icon sizing.

  ## Sizes

  - `:xs` - 12px (w-3 h-3)
  - `:sm` - 16px (w-4 h-4)
  - `:md` - 20px (w-5 h-5) - Default
  - `:lg` - 24px (w-6 h-6)
  - `:xl` - 32px (w-8 h-8)
  - `:"2xl"` - 40px (w-10 h-10)

  ## Examples

      iex> Theme.icon_size(:md)
      "w-5 h-5"
  """
  def icon_size(:xs), do: "w-3 h-3"
  def icon_size(:sm), do: "w-4 h-4"
  def icon_size(:md), do: "w-5 h-5"
  def icon_size(:lg), do: "w-6 h-6"
  def icon_size(:xl), do: "w-8 h-8"
  def icon_size(:"2xl"), do: "w-10 h-10"

  @doc """
  Returns the Tailwind spacing value (number only) for the specified size.

  Use with padding, margin, or gap classes: `p-{spacing(:md)}` → `p-4`

  ## Scale

  - `:xs` - 1 (4px)
  - `:sm` - 2 (8px)
  - `:md` - 4 (16px)
  - `:lg` - 6 (24px)
  - `:xl` - 8 (32px)
  - `:"2xl"` - 12 (48px)

  ## Examples

      iex> Theme.spacing(:md)
      "4"
  """
  def spacing(:xs), do: "1"
  def spacing(:sm), do: "2"
  def spacing(:md), do: "4"
  def spacing(:lg), do: "6"
  def spacing(:xl), do: "8"
  def spacing(:"2xl"), do: "12"

  @doc """
  Returns the shadow class for the specified level.

  ## Levels

  - `:none` - No shadow
  - `:sm` - Subtle shadow
  - `:md` - Medium shadow
  - `:lg` - Large shadow
  - `:xl` - Extra large shadow

  ## Examples

      iex> Theme.shadow(:md)
      "shadow-md"
  """
  def shadow(:none), do: "shadow-none"
  def shadow(:sm), do: "shadow-sm"
  def shadow(:md), do: "shadow-md"
  def shadow(:lg), do: "shadow-lg"
  def shadow(:xl), do: "shadow-xl"

  @doc """
  Returns typography classes for the specified style.

  Includes font size, weight, and responsive variants.

  ## Styles

  ### Display Font (Plus Jakarta Sans)
  - `:hero` - Page hero text (largest)
  - `:page_title` - Main page titles
  - `:section_title` - Section headings
  - `:cta` - Call-to-action button text

  ### Sans Font (Outfit)
  - `:card_title` - Card/component headings
  - `:body` - Default body text
  - `:body_small` - Smaller body text
  - `:caption` - Small muted text

  ## Examples

      iex> Theme.typography(:hero)
      "font-display text-4xl md:text-5xl lg:text-6xl font-bold tracking-tight"

      iex> Theme.typography(:body)
      "font-sans text-base"
  """
  def typography(:hero), do: "font-display text-4xl md:text-5xl lg:text-6xl font-bold tracking-tight"

  def typography(:page_title), do: "font-display text-3xl md:text-4xl font-bold tracking-tight"

  def typography(:section_title), do: "font-display text-2xl md:text-3xl font-bold tracking-tight"

  def typography(:cta), do: "font-display text-lg md:text-xl font-bold tracking-tight"

  def typography(:card_title), do: "font-sans text-lg font-semibold"
  def typography(:body), do: "font-sans text-base"
  def typography(:body_small), do: "font-sans text-sm"
  def typography(:caption), do: "font-sans text-xs text-gray-500"

  @doc """
  Returns the border radius class for the specified size.

  ## Sizes

  - `:none` - No rounding
  - `:sm` - Small rounding (4px)
  - `:md` - Medium rounding (8px)
  - `:lg` - Large rounding (12px)
  - `:xl` - Extra large (16px)
  - `:full` - Fully rounded (pill shape)

  ## Examples

      iex> Theme.rounded(:lg)
      "rounded-xl"
  """
  def rounded(:none), do: "rounded-none"
  def rounded(:sm), do: "rounded"
  def rounded(:md), do: "rounded-lg"
  def rounded(:lg), do: "rounded-xl"
  def rounded(:xl), do: "rounded-2xl"
  def rounded(:full), do: "rounded-full"

  @doc """
  Returns transition classes for the specified speed.

  ## Speeds

  - `:fast` - 150ms
  - `:normal` - 200ms (default)
  - `:slow` - 300ms

  ## Examples

      iex> Theme.transition(:normal)
      "transition-all duration-200"
  """
  def transition(:fast), do: "transition-all duration-150"
  def transition(:normal), do: "transition-all duration-200"
  def transition(:slow), do: "transition-all duration-300"

  @doc """
  Returns combined classes for a button variant.

  ## Variants

  - `:primary` - Primary CTA button
  - `:secondary` - Secondary action button
  - `:outline` - Bordered outline button
  - `:ghost` - Minimal/text button

  ## Examples

      iex> Theme.button_variant(:primary)
      "bg-hero-blue-600 text-white hover:bg-hero-blue-700"
  """
  def button_variant(:primary), do: "bg-hero-blue-600 text-white hover:bg-hero-blue-700"

  def button_variant(:secondary), do: "bg-hero-yellow-400 text-hero-black hover:bg-hero-yellow-500"

  def button_variant(:outline), do: "border-2 border-gray-200 text-gray-700 hover:bg-gray-50"
  def button_variant(:ghost), do: "text-gray-600 hover:bg-gray-100"

  @doc """
  Returns combined classes for a card variant.

  ## Variants

  - `:default` - Standard card with subtle shadow
  - `:elevated` - Card with larger shadow
  - `:outlined` - Card with border, no shadow
  - `:glass` - Glassmorphism effect

  ## Examples

      iex> Theme.card_variant(:default)
      "bg-white rounded-xl shadow-sm border border-gray-100"
  """
  def card_variant(:default), do: "bg-white rounded-xl shadow-sm border border-gray-100"
  def card_variant(:elevated), do: "bg-white rounded-xl shadow-lg"
  def card_variant(:outlined), do: "bg-white rounded-xl border-2 border-gray-200"
  def card_variant(:glass), do: "bg-white/80 backdrop-blur-sm rounded-xl shadow-sm"
end
