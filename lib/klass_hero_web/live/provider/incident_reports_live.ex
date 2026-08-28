defmodule KlassHeroWeb.Provider.IncidentReportsLive do
  @moduledoc """
  Provider-facing per-program incident reports listing.

  Renders all incidents tied to the program — both program-direct reports
  and reports filed against any session of that program. Ownership is
  enforced by checking the requested `program_id` against the provider's
  own programs; a foreign id redirects with a flash error.
  """

  use KlassHeroWeb, :live_view

  alias KlassHero.ProgramCatalog
  alias KlassHero.Provider
  alias KlassHero.Provider.ProviderProfile
  alias KlassHeroWeb.Presenters.IncidentReportPresenter
  alias KlassHeroWeb.Theme

  @impl true
  def mount(%{"program_id" => program_id}, _session, socket) do
    case socket.assigns.current_scope.provider do
      %ProviderProfile{} = provider ->
        mount_for_provider(socket, provider, program_id)

      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Provider profile not found."))
         |> push_navigate(to: ~p"/")}
    end
  end

  # A single scoped read verifies ownership and fetches the record, avoiding a
  # race between two queries.
  defp mount_for_provider(socket, provider, program_id) do
    case ProgramCatalog.get_program_for_provider(provider.id, program_id) do
      {:ok, program} ->
        summaries = Provider.list_incident_reports_for_program(provider.id, program_id)
        rows = Enum.map(summaries, &IncidentReportPresenter.to_list_view/1)

        {:ok,
         socket
         |> assign(
           page_title: gettext("Incident Reports"),
           active_nav: :programs,
           program: program
         )
         |> stream(:incident_reports, rows)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Program not found."))
         |> push_navigate(to: ~p"/provider/dashboard/programs")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-4 md:p-6">
      <div class="mb-6">
        <.link
          navigate={~p"/provider/dashboard/programs"}
          class="flex items-center gap-1 text-[var(--fg-muted)] hover:text-hero-grey-700 transition-colors"
        >
          <.icon name="hero-arrow-left-mini" class="w-5 h-5" />
          {gettext("Back to Programs")}
        </.link>
      </div>

      <.page_header>
        <:title>{gettext("Incident Reports")}</:title>
        <:subtitle :if={@program}>{@program.title}</:subtitle>
      </.page_header>

      <div id="incident-reports" phx-update="stream" class="mt-6 space-y-4">
        <div
          :for={{dom_id, row} <- @streams.incident_reports}
          id={dom_id}
          class={[
            "p-4 bg-white border border-hero-grey-200",
            Theme.rounded(:lg),
            Theme.shadow(:sm)
          ]}
        >
          <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-2">
            <div>
              <div class="flex items-center gap-2">
                <h3 class={[Theme.typography(:card_title)]}>
                  {row.category_label}
                </h3>
                <.status_pill color={row.severity_color}>
                  {row.severity_label}
                </.status_pill>
              </div>
              <p class={[Theme.typography(:body_small), "text-[var(--fg-muted)] mt-1"]}>
                {row.occurred_at_display} · {gettext("Submitted by")} {row.reporter_display_name}
              </p>
            </div>
          </div>
          <p class={[Theme.typography(:body_small), "mt-3 text-hero-black-100 whitespace-pre-line"]}>
            {row.description}
          </p>
        </div>

        <div id="incident-reports-empty" class="hidden only:block">
          <div class={[
            "p-8 text-center bg-white border border-hero-grey-200",
            Theme.rounded(:lg),
            Theme.shadow(:sm)
          ]}>
            <.icon name="hero-document-text" class="w-12 h-12 mx-auto mb-3 text-hero-grey-400" />
            <h3 class="text-lg font-medium text-hero-black-100 mb-1">
              {gettext("No incident reports yet")}
            </h3>
            <p class="text-[var(--fg-muted)]">
              {gettext("Reports filed for this program will appear here.")}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
