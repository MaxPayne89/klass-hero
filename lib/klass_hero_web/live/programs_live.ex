defmodule KlassHeroWeb.ProgramsLive do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.MarketingComponents
  import KlassHeroWeb.ProgramComponents

  alias KlassHero.ProgramCatalog
  alias KlassHero.ProgramCatalog.Program
  alias KlassHero.Shared.ErrorIds
  alias KlassHeroWeb.Helpers.ProviderDisplay
  alias KlassHeroWeb.Presenters.ProgramPresenter

  require Logger

  @valid_sorts ~w(recommended newest price_low price_high)

  defp filter_options do
    [
      %{id: "all", label: gettext("All")},
      %{id: "sports", label: gettext("Sports")},
      %{id: "arts", label: gettext("Arts")},
      %{id: "music", label: gettext("Music")},
      %{id: "education", label: gettext("Education")},
      %{id: "life-skills", label: gettext("Life Skills")},
      %{id: "camps", label: gettext("Camps")},
      %{id: "workshops", label: gettext("Workshops")}
    ]
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: gettext("Explore Programs"))
      |> assign(active_nav: :programs)
      |> assign(search_query: "")
      |> assign(active_filter: "all")
      |> assign(sort_by: "recommended")
      |> assign(view_mode: :grid)
      |> stream(:programs, [])
      |> assign(loaded_programs: [])
      |> assign(programs_count: 0)
      |> assign(programs_empty?: true)
      |> assign(filters: filter_options())
      |> assign(page_size: 20)
      |> assign(next_cursor: nil)
      |> assign(has_more: false)
      |> assign(loading_more: false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    search_query = ProgramCatalog.sanitize_query(params["q"])
    active_filter = ProgramCatalog.validate_category_filter(params["filter"])
    sort_by = sanitize_sort(params["sort"])

    {:ok, page_result} =
      ProgramCatalog.list_programs_paginated(socket.assigns.page_size, nil, active_filter)

    start_time = System.monotonic_time(:millisecond)
    filtered_domain = ProgramCatalog.filter_programs(page_result.items, search_query)
    sorted_domain = apply_sort(filtered_domain, sort_by)
    program_ids = Enum.map(sorted_domain, & &1.id)
    capacities = ProgramCatalog.remaining_capacities(program_ids)
    providers = ProviderDisplay.for_programs(sorted_domain)
    programs = Enum.map(sorted_domain, &program_to_map(&1, capacities, providers))
    duration_ms = System.monotonic_time(:millisecond) - start_time

    Logger.info(
      "[ProgramsLive.handle_params] Filter operation completed",
      search_query: search_query,
      category: active_filter,
      sort: sort_by,
      result_count: length(programs),
      page_has_more: page_result.has_more,
      duration_ms: duration_ms,
      current_user_id: get_user_id(socket)
    )

    if duration_ms > 150 do
      Logger.warning(
        "[ProgramsLive.handle_params] Filter operation exceeded performance target",
        search_query: search_query,
        category: active_filter,
        sort: sort_by,
        result_count: length(programs),
        duration_ms: duration_ms,
        target_ms: 150,
        current_user_id: get_user_id(socket)
      )
    end

    socket =
      socket
      |> assign(search_query: search_query)
      |> assign(active_filter: active_filter)
      |> assign(sort_by: sort_by)
      |> assign(next_cursor: page_result.next_cursor)
      # Load-more disabled for non-recommended sorts: merging paginated batches would
      # break the visual order (follow-up: pass sort to list_programs_paginated/3).
      |> assign(has_more: page_result.has_more and sort_by == "recommended")
      |> stream(:programs, programs, reset: true)
      |> assign(loaded_programs: programs)
      |> assign(programs_count: length(programs))
      |> assign(:programs_empty?, Enum.empty?(programs))

    {:noreply, socket}
  end

  defp program_to_map(%Program{} = program, capacities, providers) do
    remaining = Map.get(capacities, program.id)
    spots_left = if remaining != :unlimited, do: remaining

    ProgramPresenter.to_card_view(program, ProviderDisplay.fetch(providers, program), spots_left)
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    params = build_query_params(socket.assigns, q: query)
    {:noreply, push_patch(socket, to: ~p"/programs?#{params}")}
  end

  @impl true
  def handle_event("filter_select", %{"filter" => filter_id}, socket) do
    params = build_query_params(socket.assigns, filter: filter_id)
    {:noreply, push_patch(socket, to: ~p"/programs?#{params}")}
  end

  @impl true
  def handle_event("sort_select", %{"sort" => sort_key}, socket) do
    params = build_query_params(socket.assigns, sort: sort_key)
    {:noreply, push_patch(socket, to: ~p"/programs?#{params}")}
  end

  @impl true
  def handle_event("toggle_view", %{"view" => view}, socket) do
    view_mode = if view == "list", do: :list, else: :grid

    # Stream entries render-cache by id: switching :view_mode leaves the
    # existing entry components in place. Re-stream the already-loaded
    # programs (page 1 + any load_more pages) so view-mode-aware entry
    # components re-render without a DB round-trip.
    socket =
      socket
      |> assign(view_mode: view_mode)
      |> stream(:programs, socket.assigns.loaded_programs, reset: true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/programs")}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    socket = assign(socket, loading_more: true)

    case ProgramCatalog.list_programs_paginated(
           socket.assigns.page_size,
           socket.assigns.next_cursor,
           socket.assigns.active_filter
         ) do
      {:ok, page_result} ->
        filtered_domain =
          ProgramCatalog.filter_programs(page_result.items, socket.assigns.search_query)

        program_ids = Enum.map(filtered_domain, & &1.id)
        capacities = ProgramCatalog.remaining_capacities(program_ids)
        providers = ProviderDisplay.for_programs(filtered_domain)
        programs = Enum.map(filtered_domain, &program_to_map(&1, capacities, providers))

        Logger.info(
          "[ProgramsLive.load_more] Successfully loaded next page",
          returned_count: length(programs),
          has_more: page_result.has_more,
          category: socket.assigns.active_filter,
          current_user_id: get_user_id(socket)
        )

        socket =
          socket
          |> assign(next_cursor: page_result.next_cursor)
          |> assign(has_more: page_result.has_more)
          |> assign(loading_more: false)
          |> assign(loaded_programs: socket.assigns.loaded_programs ++ programs)
          |> assign(programs_count: socket.assigns.programs_count + length(programs))
          |> stream(:programs, programs)

        {:noreply, socket}

      {:error, :invalid_cursor} ->
        Logger.warning(
          "[ProgramsLive.load_more] Invalid cursor",
          error_id: ErrorIds.program_pagination_invalid_cursor(),
          current_user_id: get_user_id(socket),
          live_view: __MODULE__
        )

        socket =
          socket
          |> assign(loading_more: false)
          |> put_flash(:error, gettext("Invalid pagination state. Please refresh the page."))

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("program_click", %{"program-id" => program_id}, socket) do
    Logger.info(
      "[ProgramsLive.program_click] Navigating to program detail",
      program_id: program_id,
      current_user_id: get_user_id(socket)
    )

    {:noreply, push_navigate(socket, to: ~p"/programs/#{program_id}")}
  end

  defp sanitize_sort(sort) when sort in @valid_sorts, do: sort
  defp sanitize_sort(_), do: "recommended"

  defp apply_sort(programs, "newest") do
    Enum.sort_by(programs, & &1.inserted_at, {:desc, DateTime})
  end

  defp apply_sort(programs, "price_low") do
    Enum.sort_by(programs, &price_for_sort/1, :asc)
  end

  defp apply_sort(programs, "price_high") do
    Enum.sort_by(programs, &price_for_sort/1, :desc)
  end

  defp apply_sort(programs, _recommended), do: programs

  defp price_for_sort(%Program{price: nil}), do: 0
  defp price_for_sort(%Program{price: %Decimal{} = d}), do: Decimal.to_float(d)
  defp price_for_sort(%Program{price: p}) when is_number(p), do: p

  defp build_query_params(assigns, updates) do
    updates_map = Map.new(updates, fn {k, v} -> {to_string(k), v} end)

    %{
      "q" => assigns.search_query,
      "filter" => assigns.active_filter,
      "sort" => assigns.sort_by
    }
    |> Map.merge(updates_map)
    |> Enum.reject(fn
      {_k, ""} -> true
      {"filter", "all"} -> true
      {"sort", "recommended"} -> true
      _ -> false
    end)
    |> Map.new()
  end

  defp get_user_id(socket) do
    case socket.assigns[:current_scope] do
      %{user: %{id: id}} -> id
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.mk_programs_hero
      search_query={@search_query}
      active_filter={@active_filter}
      filters={@filters}
    />

    <section class="bg-white pb-20">
      <div class="max-w-7xl mx-auto px-6">
        <.mk_programs_controls
          count={@programs_count}
          search_query={@search_query}
          active_filter={@active_filter}
          filters={@filters}
          sort={@sort_by}
          view_mode={@view_mode}
        />

        <%= if @programs_empty? do %>
          <.mk_empty_state
            title={gettext("No programs found")}
            description={
              gettext("Try adjusting your search or filter criteria — there's plenty more in Berlin.")
            }
            clear_event="clear_filters"
          />
        <% else %>
          <%!-- Single stream container, layout class swaps on @view_mode. Switching the
                container id would shed the stream entries (LV tracks children by id within
                a stable container). The :if branches below render different components per
                entry but each sets `id={dom_id}`, so stream patching stays consistent. --%>
          <div
            id="mk-programs-stream"
            phx-update="stream"
            data-view={Atom.to_string(@view_mode)}
            class={[
              "mt-8",
              if(@view_mode == :list,
                do: "space-y-4",
                else: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6"
              )
            ]}
          >
            <%= for {dom_id, program} <- @streams.programs do %>
              <%= if @view_mode == :list do %>
                <.mk_program_list_row id={dom_id} program={program} />
              <% else %>
                <.program_card
                  id={dom_id}
                  data-program-id={program.id}
                  program={program}
                  variant={:detailed}
                  phx-click="program_click"
                  phx-value-program-id={program.id}
                  phx-value-program-title={program.title}
                />
              <% end %>
            <% end %>
          </div>
        <% end %>

        <div :if={@has_more and not @programs_empty?} class="flex justify-center mt-12">
          <button
            type="button"
            phx-click="load_more"
            disabled={@loading_more}
            class={
              [
                "px-6 py-3 bg-hero-black text-white rounded-xl hover:bg-[var(--brand-primary-dark)] transition-colors cursor-pointer disabled:opacity-60 disabled:cursor-not-allowed",
                # typography-lint-ignore: load-more CTA mirrors marketing button display style on dark surface
                "font-display font-bold"
              ]
            }
          >
            <%= if @loading_more do %>
              {gettext("Loading...")}
            <% else %>
              {gettext("Load more programs")}
            <% end %>
          </button>
        </div>
      </div>
    </section>
    """
  end
end
