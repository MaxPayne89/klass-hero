defmodule KlassHeroWeb.Admin.Components.SearchableSelect do
  @moduledoc """
  Reusable searchable dropdown LiveComponent for admin views.

  Encapsulates dropdown state (search term, open/closed, filtered options).
  LiveComponent is necessary here because each instance needs independent
  mutable state — a function component cannot hold per-instance state.

  ## Usage from a parent LiveView

      <.live_component
        module={SearchableSelect}
        id="provider-select"
        label="Provider"
        placeholder="All providers"
        field_name="provider_id"
        options={@providers}
        selected={@selected_provider}
      />

  When the user selects an option, sends to parent:
  `{:select, "provider_id", %{id: "uuid", label: "Name"}}`

  When the user clears the selection, sends:
  `{:select, "provider_id", nil}`
  """

  use KlassHeroWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:search_term, "")
     |> assign(:open?, false)}
  end

  @impl true
  def update(%{id: id} = assigns, socket) do
    options = assigns[:options] || []
    selected = assigns[:selected]
    current_term = socket.assigns[:search_term] || ""

    # Skip re-filtering when options haven't changed — parent re-renders frequently.
    filtered =
      if options == socket.assigns[:options] do
        socket.assigns[:filtered_options] || options
      else
        filter_options(options, current_term)
      end

    {:ok,
     socket
     |> assign(:id, id)
     |> assign(:label, assigns[:label] || "")
     |> assign(:placeholder, assigns[:placeholder] || "Search...")
     |> assign(:field_name, assigns[:field_name] || "")
     |> assign(:options, options)
     |> assign(:selected, selected)
     |> assign(:filtered_options, filtered)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="relative" phx-click-away="close" phx-target={@myself}>
      <label :if={@label != ""} class="label label-text text-xs font-medium uppercase tracking-wide">
        {@label}
      </label>

      <div :if={@selected} class="flex items-center gap-2">
        <span class="input input-bordered input-sm flex-1 flex items-center">
          {@selected.label}
        </span>
        <button
          type="button"
          phx-click="clear"
          phx-target={@myself}
          class="btn btn-ghost btn-xs"
          aria-label={gettext("Clear selection")}
        >
          ×
        </button>
        <input type="hidden" name={@field_name} value={@selected.id} />
      </div>

      <%!-- Wrap in <form> because phx-change requires a form ancestor --%>
      <form :if={!@selected} phx-change="search" phx-submit="noop" phx-target={@myself}>
        <input
          type="text"
          placeholder={@placeholder}
          value={@search_term}
          phx-focus="open"
          phx-debounce="300"
          phx-target={@myself}
          name={"#{@field_name}_search"}
          class="input input-bordered input-sm w-full"
          autocomplete="off"
        />
        <input type="hidden" name={@field_name} value="" />

        <ul
          :if={@open?}
          class="absolute z-50 mt-1 w-full bg-base-100 border border-base-300 rounded-lg shadow-lg max-h-48 overflow-y-auto"
        >
          <li :if={@filtered_options == []} class="px-3 py-2 text-sm opacity-50">
            {gettext("No results")}
          </li>
          <li
            :for={option <- @filtered_options}
            phx-click="select"
            phx-value-id={option.id}
            phx-value-label={option.label}
            phx-target={@myself}
            class="px-3 py-2 text-sm cursor-pointer hover:bg-base-200"
          >
            {option.label}
          </li>
        </ul>
      </form>
    </div>
    """
  end

  @impl true
  def handle_event("search", params, socket) do
    # Form params include a hidden field; extract only the search input by its name key.
    search_key = "#{socket.assigns.field_name}_search"
    term = params[search_key] || ""

    {:noreply,
     socket
     |> assign(:search_term, term)
     |> assign(:open?, true)
     |> assign(:filtered_options, filter_options(socket.assigns.options, term))}
  end

  @impl true
  def handle_event("open", _params, socket) do
    {:noreply, assign(socket, :open?, true)}
  end

  @impl true
  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, :open?, false)}
  end

  @impl true
  def handle_event("select", %{"id" => id, "label" => label}, socket) do
    selected = %{id: id, label: label}
    send(self(), {:select, socket.assigns.field_name, selected})

    {:noreply,
     socket
     |> assign(:selected, selected)
     |> assign(:search_term, "")
     |> assign(:open?, false)}
  end

  @impl true
  def handle_event("clear", _params, socket) do
    send(self(), {:select, socket.assigns.field_name, nil})

    {:noreply,
     socket
     |> assign(:selected, nil)
     |> assign(:search_term, "")
     |> assign(:open?, false)}
  end

  @impl true
  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  defp filter_options(options, ""), do: options

  defp filter_options(options, term) do
    downcased = String.downcase(term)
    Enum.filter(options, fn opt -> String.contains?(String.downcase(opt.label), downcased) end)
  end
end
