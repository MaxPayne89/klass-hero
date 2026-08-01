defmodule KlassHeroWeb.Admin.Components.SearchableSelectTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHeroWeb.Admin.Components.SearchableSelect

  @options [
    %{id: "id-1", label: "Alpha Arts"},
    %{id: "id-2", label: "Beta Sports"},
    %{id: "id-3", label: "Creative Learning"}
  ]

  # Test harness LiveView to host the LiveComponent for isolated testing.
  # LiveComponents cannot be tested with live_isolated — they need a parent LiveView.
  defmodule HarnessLive do
    use KlassHeroWeb, :live_view

    @impl true
    def mount(_params, session, socket) do
      socket =
        socket
        |> Phoenix.Component.assign(:options, session["options"] || [])
        |> Phoenix.Component.assign(:selected, session["selected"])
        |> Phoenix.Component.assign(:label, session["label"] || "Test")
        |> Phoenix.Component.assign(:placeholder, session["placeholder"] || "Search...")
        |> Phoenix.Component.assign(:field_name, session["field_name"] || "test_field")
        |> Phoenix.Component.assign(:select_events, [])

      {:ok, socket}
    end

    @impl true
    def handle_info({:select, field_name, selected}, socket) do
      socket =
        socket
        |> Phoenix.Component.assign(:selected, selected)
        |> update(:select_events, &[{field_name, selected} | &1])

      {:noreply, socket}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div id="harness">
        <.live_component
          module={SearchableSelect}
          id="test-select"
          label={@label}
          placeholder={@placeholder}
          field_name={@field_name}
          options={@options}
          selected={@selected}
        />
        <span id="event-count">{length(@select_events)}</span>
      </div>
      """
    end
  end

  defp mount_harness(conn, opts \\ %{}) do
    session =
      Map.merge(
        %{
          "options" => @options,
          "selected" => nil,
          "label" => "Provider",
          "placeholder" => "All providers",
          "field_name" => "provider_id"
        },
        opts
      )

    live_isolated(conn, HarnessLive, session: session)
  end

  describe "rendering" do
    test "renders label and placeholder", %{conn: conn} do
      {:ok, view, html} = mount_harness(conn)

      assert html =~ "Provider"
      assert has_element?(view, "[placeholder=\"All providers\"]")
    end

    test "renders hidden input with field_name", %{conn: conn} do
      {:ok, view, _html} = mount_harness(conn)

      assert has_element?(view, "input[type=hidden][name=provider_id]")
    end

    test "derives the search form id from the component id, so it can be recovered", %{conn: conn} do
      {:ok, view, _html} = mount_harness(conn)

      # Must not reuse @id itself — that belongs to the outer <div>, and a duplicate DOM id
      # trips LiveViewTest's :duplicate_id check, which raises by default.
      assert has_element?(view, "form#test-select-search-form[phx-change=search]")
      assert has_element?(view, "div#test-select")
    end
  end

  describe "filtering" do
    test "filters options by search term (case-insensitive)", %{conn: conn} do
      {:ok, view, _html} = mount_harness(conn)

      # Target the form (which has phx-change), not the input — LiveViewTest
      # requires phx-change to be on the element passed to render_change/2.
      view
      |> element("form[phx-change=search]")
      |> render_change(%{"provider_id_search" => "alpha"})

      html = render(view)
      assert html =~ "Alpha Arts"
      refute html =~ "Beta Sports"
      refute html =~ "Creative Learning"
    end

    test "shows 'No results' when nothing matches", %{conn: conn} do
      {:ok, view, _html} = mount_harness(conn)

      view
      |> element("form[phx-change=search]")
      |> render_change(%{"provider_id_search" => "nonexistent"})

      assert render(view) =~ "No results"
    end
  end

  describe "selection" do
    test "displays selected value and clear button", %{conn: conn} do
      selected = %{id: "id-1", label: "Alpha Arts"}

      {:ok, view, _html} = mount_harness(conn, %{"selected" => selected})

      html = render(view)
      assert html =~ "Alpha Arts"
      assert has_element?(view, "input[type=hidden][name=provider_id][value=id-1]")
      assert has_element?(view, "button[phx-click=clear]")
    end
  end
end
