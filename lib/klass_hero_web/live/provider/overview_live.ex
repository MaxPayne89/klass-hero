defmodule KlassHeroWeb.Provider.OverviewLive do
  @moduledoc """
  Provider dashboard overview: KPI stats, top programs, pending booking requests,
  pending enrollments, and the business profile card.

  Split out of the former `DashboardLive` god-module (#904) — the landing tab at
  /provider/dashboard. It is the only tab that subscribes to PubSub (session-stats
  and enrollment-confirmed), so it owns all `handle_info/2` clauses. Renders inside
  the shared `pv_dashboard_shell`.
  """
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.ProviderComponents

  alias KlassHero.Enrollment
  alias KlassHero.ProgramCatalog
  alias KlassHero.ProgramCatalog.ProgramListing
  alias KlassHero.Provider
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHeroWeb.Presenters.ProviderPresenter
  alias KlassHeroWeb.Provider.Dashboard.Chrome

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    provider = socket.assigns.current_scope.provider

    docs = fetch_verification_docs(provider.id)
    verification_status = ProviderPresenter.verification_status_from_docs(provider.verified, docs)

    total_sessions = Provider.get_total_session_count(provider.id)

    program_listings = ProgramCatalog.list_programs_for_provider(provider.id)
    program_ids = Enum.map(program_listings, & &1.id)

    enrollment_counts = Enrollment.count_active_enrollments_batch(program_ids)
    enrolled_total = enrollment_counts |> Map.values() |> Enum.sum()

    pending_requests = load_pending_requests(program_ids)
    pending_enrollments = Enrollment.list_pending_enrollments_for_provider(program_ids)
    top_programs = build_top_programs(program_listings, enrollment_counts)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(KlassHero.PubSub, "provider:#{provider.id}:stats_updated")

      Phoenix.PubSub.subscribe(
        KlassHero.PubSub,
        Enrollment.provider_scoped_topic(:enrollment_confirmed, provider.id)
      )
    end

    socket = Chrome.assign(socket)
    business = %{socket.assigns.business | verification_status: verification_status}

    socket =
      socket
      |> assign(page_title: gettext("Provider Dashboard"))
      |> assign(business: business)
      |> assign(programs_count: length(program_listings))
      |> assign(total_sessions_completed: total_sessions)
      |> assign(enrolled_total: enrolled_total)
      |> assign(pending_requests: pending_requests)
      |> assign(pending_enrollments: pending_enrollments)
      |> assign(top_programs: top_programs)

    {:ok, socket}
  end

  @impl true
  def handle_event("approve_enrollment", %{"id" => enrollment_id}, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    case Enrollment.confirm_enrollment(%{
           enrollment_id: enrollment_id,
           provider_id: provider_id
         }) do
      {:ok, _enrollment} ->
        # No refresh here — :enrollment_confirmed loopback drives it (handle_info/2).
        {:noreply, put_flash(socket, :info, gettext("Enrollment approved"))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Not allowed to approve this enrollment"))}

      {:error, :invalid_status_transition} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Enrollment is not pending"))
         |> refresh_pending_enrollments()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Enrollment not found"))}

      {:error, reason} ->
        Logger.error("[Dashboard.approve_enrollment] Failed",
          enrollment_id: enrollment_id,
          provider_id: provider_id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Failed to approve"))}
    end
  end

  # The shared dashboard header's "New Program" CTA lives on every tab; from
  # Overview it navigates to the Programs tab with the create form opened.
  @impl true
  def handle_event("add_program", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/provider/dashboard/programs?new=1")}
  end

  @impl true
  def handle_info(:session_stats_updated, socket) do
    provider = socket.assigns.current_scope.provider
    new_count = Provider.get_total_session_count(provider.id)

    if new_count == socket.assigns.total_sessions_completed do
      {:noreply, socket}
    else
      {:noreply, assign(socket, total_sessions_completed: new_count)}
    end
  end

  @impl true
  def handle_info({:domain_event, %DomainEvent{event_type: :enrollment_confirmed}}, socket) do
    {:noreply, refresh_pending_enrollments(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp fetch_verification_docs(provider_id) do
    {:ok, docs} = Provider.get_provider_verification_documents(provider_id)
    docs
  end

  defp load_pending_requests(program_ids) do
    palette = ["#FFEAC9", "#33CFFF", "#FFFF36", "#FFD896"]

    program_ids
    |> Enum.flat_map(&safe_list_invites/1)
    |> Enum.with_index()
    |> Enum.map(fn {invite, idx} ->
      %{
        id: invite.id,
        parent: invite.invitee_name || invite.invitee_email || "Unknown",
        program: invite.program_id,
        child: invite[:child_name] || "—",
        when: invite[:created_at] && Calendar.strftime(invite.created_at, "%b %d"),
        color: Enum.at(palette, rem(idx, length(palette)))
      }
    end)
    |> Enum.take(5)
  end

  defp safe_list_invites(program_id) do
    {:ok, invites} = Enrollment.list_program_invites(program_id)
    Enum.filter(invites, &(&1.status == :pending))
  end

  # Top 5 provider programs sorted by active-enrollment count desc.
  # Source is the rich %ProgramListing{} already loaded in mount.
  defp build_top_programs(listings, enrollment_counts) do
    today = Date.utc_today()

    listings
    |> Enum.map(&build_program_row(&1, enrollment_counts, today))
    |> Enum.sort_by(& &1.booked, :desc)
    |> Enum.take(5)
  end

  defp build_program_row(%ProgramListing{} = p, enrollment_counts, today) do
    %{
      id: p.id,
      title: p.title,
      booked: Map.get(enrollment_counts, p.id, 0),
      status: derive_program_status(p, today),
      cover: p.cover_image_url && "url(#{p.cover_image_url})"
    }
  end

  # %ProgramListing{} carries no explicit status; derive a coarse pill from its
  # registration and run-window dates. :full is capacity-driven and out of scope
  # here — capacity isn't projected onto the listing read model.
  defp derive_program_status(%ProgramListing{} = p, today) do
    cond do
      not_yet_open?(p.registration_start_date, today) -> :draft
      past?(p.registration_end_date, today) -> :archived
      past?(p.end_date, today) -> :archived
      true -> :live
    end
  end

  defp not_yet_open?(nil, _today), do: false
  defp not_yet_open?(start_date, today), do: Date.before?(today, start_date)

  defp past?(nil, _today), do: false
  defp past?(date, today), do: Date.after?(today, date)

  defp refresh_pending_enrollments(socket) do
    provider = socket.assigns.current_scope.provider
    program_ids = ProgramCatalog.list_programs_for_provider(provider.id) |> Enum.map(& &1.id)
    assign(socket, :pending_enrollments, Enrollment.list_pending_enrollments_for_provider(program_ids))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.pv_dashboard_shell
      business={@business}
      current_tab={:overview}
      profile_draft?={@profile_draft?}
      dual_role?={@dual_role?}
    >
      <div class="space-y-6">
        <%!-- 4-up KPI grid. Revenue + Rating disabled until Stripe transactions
              and a review/rating model land. --%>
        <section id="provider-dashboard-stats" class="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <.pv_stat_card
            title={gettext("Active programs")}
            value={Integer.to_string(@programs_count)}
            icon="hero-academic-cap"
            tone={:primary}
          />
          <.pv_stat_card
            title={gettext("Enrolled kids")}
            value={Integer.to_string(@enrolled_total)}
            icon="hero-users"
            tone={:cool}
            caption={gettext("Across all programs")}
          />
          <.pv_stat_card
            title={gettext("Revenue (this week)")}
            value="—"
            icon="hero-currency-euro"
            tone={:safety}
            disabled={true}
            caption={gettext("Coming soon")}
          />
          <.pv_stat_card
            title={gettext("Rating")}
            value="—"
            icon="hero-star"
            tone={:art}
            disabled={true}
            caption={gettext("Coming soon")}
          />
        </section>

        <section id="provider-earnings-chart">
          <.pv_earnings_chart data={[]} />
        </section>

        <section class="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <.kh_card class="p-5">
            <div class="flex items-center justify-between mb-4">
              <h3 class="font-bold text-lg">{gettext("Your top programs")}</h3>
              <.link
                navigate={~p"/provider/dashboard/programs"}
                class="text-sm font-bold text-[var(--brand-primary-dark)]"
              >
                {gettext("Manage")} →
              </.link>
            </div>
            <div :if={@top_programs == []} class="text-sm text-hero-grey-600">
              {gettext("No programs yet — add your first one from the Programs tab.")}
            </div>
            <div class="space-y-1">
              <.pv_program_row :for={p <- @top_programs} program={p} />
            </div>
          </.kh_card>

          <.kh_card class="p-5">
            <div class="flex items-center justify-between mb-4">
              <h3 class="font-bold text-lg">{gettext("Pending booking requests")}</h3>
              <span class="text-xs text-hero-grey-600 font-semibold">
                {length(@pending_requests)} {gettext("pending")}
              </span>
            </div>
            <div :if={@pending_requests == []} class="text-sm text-hero-grey-600">
              {gettext("No pending requests right now.")}
            </div>
            <div class="space-y-3">
              <.pv_request_card :for={r <- @pending_requests} request={r} />
            </div>
          </.kh_card>

          <.kh_card id="pending-enrollments-card" class="p-5">
            <div class="flex items-center justify-between mb-4">
              <h3 class="font-bold text-lg">{gettext("Pending enrollments")}</h3>
              <span class="text-xs text-hero-grey-600 font-semibold">
                {length(@pending_enrollments)} {gettext("pending")}
              </span>
            </div>
            <div :if={@pending_enrollments == []} class="text-sm text-hero-grey-600">
              {gettext("No pending enrollments right now.")}
            </div>
            <div class="space-y-3">
              <.pv_pending_enrollment_card
                :for={entry <- @pending_enrollments}
                entry={entry}
              />
            </div>
          </.kh_card>
        </section>

        <.business_profile_card business={@business} />
      </div>
    </.pv_dashboard_shell>
    """
  end
end
