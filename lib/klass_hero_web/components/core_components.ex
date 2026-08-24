defmodule KlassHeroWeb.CoreComponents do
  @moduledoc """
  Core UI components used across the application.
  """
  use Phoenix.Component
  use Gettext, backend: KlassHeroWeb.Gettext

  import KlassHeroWeb.UIComponents, only: [icon: 1]

  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error, :warning], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <%!-- z-[60] sits above modal chrome (z-50) rather than level with it. A flash
          rendered earlier in the DOM at the same z-index loses to the modal painted
          over it, which silently swallowed every error raised from inside one — and
          a refusal the user never sees reads as a frozen panel. --%>
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="fixed top-4 right-4 z-[60] max-w-md"
      {@rest}
    >
      <div class={[
        "rounded-xl shadow-lg p-4 flex items-start gap-3",
        @kind == :info && "bg-blue-50 border border-blue-200",
        @kind == :error && "bg-red-50 border border-red-200",
        @kind == :warning && "bg-yellow-50 border border-yellow-200"
      ]}>
        <.icon
          :if={@kind == :info}
          name="hero-information-circle"
          class="w-5 h-5 text-blue-500 flex-shrink-0"
        />
        <.icon
          :if={@kind == :error}
          name="hero-exclamation-circle"
          class="w-5 h-5 text-red-500 flex-shrink-0"
        />
        <.icon
          :if={@kind == :warning}
          name="hero-exclamation-triangle"
          class="w-5 h-5 text-yellow-500 flex-shrink-0"
        />
        <div class="flex-1">
          <p :if={@title} class="font-semibold text-gray-900 mb-1">{@title}</p>
          <p class="text-sm text-gray-700">{msg}</p>
        </div>
        <button type="button" class="flex-shrink-0" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="w-5 h-5 text-gray-400 hover:text-gray-600" />
        </button>
      </div>
    </div>
    """
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(KlassHeroWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(KlassHeroWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates a Backpex message through our Gettext backend using the "backpex" domain.
  Wired into `:backpex, :translator_function` in config.exs to silence the fallback warning
  and let us override strings via `priv/gettext/<locale>/LC_MESSAGES/backpex.po`.
  """
  def translate_backpex({msg, opts}) do
    Gettext.dgettext(KlassHeroWeb.Gettext, "backpex", msg, opts)
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class="mb-6">
      <div>
        <h1 class="text-2xl font-semibold text-gray-900 leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm text-gray-600 leading-6">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div :if={@actions != []} class="mt-4 flex-none">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  @doc """
  Renders an input with label and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week)

  attr :field, FormField, doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :pill, :boolean,
    default: false,
    doc: "Renders the input with rounded-full corners (matches KhInput pill variant)"

  attr :icon, :string,
    default: nil,
    doc: "Heroicon name rendered inside the input on the leading edge"

  attr :rest, :global, include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  slot :inner_block

  def input(%{field: %FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error/1))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div phx-feedback-for={@name}>
      <label class="flex items-center gap-4 text-sm leading-6 text-hero-black-100">
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-2 border-hero-grey-300 text-hero-blue-600 focus:ring-2 focus:ring-[var(--focus-ring)]/20 focus:ring-offset-0 shadow-sm transition-all duration-200"
          {@rest}
        />
        {@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class="mt-2 block w-full rounded-lg border-2 border-hero-grey-300 bg-white/90 backdrop-blur-sm shadow-sm focus:border-hero-blue-500 focus:ring-2 focus:ring-[var(--focus-ring)]/20 focus:shadow-md sm:text-sm transition-all duration-200"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-2 block w-full rounded-lg text-hero-black sm:text-sm sm:leading-6",
          "min-h-[6rem]",
          "bg-white/90 backdrop-blur-sm",
          "border-2",
          "phx-no-feedback:border-hero-grey-300 phx-no-feedback:focus:border-hero-blue-500",
          @errors == [] && "border-hero-grey-300 focus:border-hero-blue-500",
          @errors != [] && "border-rose-500 focus:border-rose-600",
          "shadow-sm focus:shadow-md",
          "transition-all duration-200",
          "focus:ring-2 focus:ring-[var(--focus-ring)]/20 focus:ring-offset-0"
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <div class="relative">
        <div
          :if={@icon}
          class="absolute left-3.5 top-1/2 -translate-y-1/2 text-[var(--fg-muted)] pointer-events-none"
        >
          <.icon name={@icon} class="w-4 h-4" />
        </div>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            "mt-2 block w-full text-hero-black sm:text-sm sm:leading-6",
            if(@pill, do: "rounded-full", else: "rounded-lg"),
            if(@icon, do: "pl-10", else: nil),
            "bg-white/90 backdrop-blur-sm",
            "border-2",
            "phx-no-feedback:border-hero-grey-300 phx-no-feedback:focus:border-hero-blue-500",
            @errors == [] && "border-hero-grey-300 focus:border-hero-blue-500",
            @errors != [] && "border-rose-500 focus:border-rose-600",
            "shadow-sm focus:shadow-md",
            "transition-all duration-200",
            "focus:ring-2 focus:ring-[var(--focus-ring)]/20 focus:ring-offset-0"
          ]}
          {@rest}
        />
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-hero-black">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm leading-6 text-rose-600 phx-no-feedback:hidden">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a button.
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg bg-hero-blue-600 hover:bg-hero-blue-700 py-2 px-3",
        "text-sm font-semibold leading-6 text-white active:text-white/80",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end
end
