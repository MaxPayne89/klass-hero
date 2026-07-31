defmodule KlassHeroWeb.Layouts do
  @moduledoc """
  Layouts and shared layout components.
  """
  use KlassHeroWeb, :html

  # Must precede embed_templates: aliases are lexically scoped and the templates
  # compile at that call site, so root.html.heex would not resolve `Locale`.
  alias KlassHeroWeb.Locale

  # The root layout renders on dead render only — which is exactly what crawlers
  # see — so the request path SetLocale assigned is enough here; no per-navigation
  # LiveView hook is needed.
  defp seo_path(assigns), do: assigns[:current_path] || "/"

  embed_templates "layouts/*"

  @doc """
  Renders info, error, and warning flashes plus reconnect notices.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
      <.flash kind={:warning} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Language switcher pill for German/English; switches via `?locale=` query param.

  ## Examples

      <.language_switcher locale={@locale} />
  """
  attr :locale, :string, default: "en", doc: "Current locale (en or de)"

  def language_switcher(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class={[
        "absolute w-1/2 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 transition-[left]",
        if(@locale == "en", do: "left-0", else: "left-1/2")
      ]} />

      <.link
        href="?locale=en"
        class={[
          "flex items-center gap-1 px-3 py-2 cursor-pointer w-1/2 text-sm font-medium z-10",
          if(@locale == "en", do: "opacity-100", else: "opacity-60 hover:opacity-100")
        ]}
      >
        <span class="text-base">🇬🇧</span>
        <span class="hidden sm:inline">EN</span>
      </.link>

      <.link
        href="?locale=de"
        class={[
          "flex items-center gap-1 px-3 py-2 cursor-pointer w-1/2 text-sm font-medium z-10",
          if(@locale == "de", do: "opacity-100", else: "opacity-60 hover:opacity-100")
        ]}
      >
        <span class="text-base">🇩🇪</span>
        <span class="hidden sm:inline">DE</span>
      </.link>
    </div>
    """
  end

  attr :flash, :map, required: true
  attr :fluid?, :boolean, default: true
  attr :current_url, :string, required: true
  attr :live_resource, :atom, default: nil
  slot :inner_block, required: true

  def admin(assigns)
end
