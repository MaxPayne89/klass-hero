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
  alias KlassHeroWeb.Presenters.ProviderPresenter
  alias KlassHeroWeb.Provider.Dashboard.Chrome
  alias KlassHeroWeb.Provider.Dashboard.InviteActions
  alias KlassHeroWeb.Theme

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

    outstanding_invites = Enrollment.list_outstanding_invites_for_provider(provider.id)
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
      |> assign(active_nav: :home)
      |> assign(business: business)
      |> assign(identity_verified?: Provider.identity_step_approved?(provider.id))
      |> assign(programs_count: length(program_listings))
      |> assign(total_sessions_completed: total_sessions)
      |> assign(enrolled_total: enrolled_total)
      |> assign(outstanding_invites: outstanding_invites)
      |> assign(invites_modal_open?: false)
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

  @impl true
  def handle_event("open_invites", _params, socket) do
    {:noreply, assign(socket, :invites_modal_open?, true)}
  end

  @impl true
  def handle_event("close_invites", _params, socket) do
    {:noreply, assign(socket, :invites_modal_open?, false)}
  end

  @impl true
  def handle_event("resend_invite", %{"id" => invite_id}, socket) do
    {:noreply, invite_action(&InviteActions.resend/4, invite_id, socket)}
  end

  @impl true
  def handle_event("delete_invite", %{"id" => invite_id}, socket) do
    {:noreply, invite_action(&InviteActions.delete/4, invite_id, socket)}
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

  # The confirmed enrollment's id is on the message and on each pending read-model
  # entry, so the loopback can drop the row from assigns without a DB round-trip.
  # Fall back to a refresh only on a cross-tab miss (another tab approved before
  # this one loaded, so the id isn't in local assigns yet).
  @impl true
  def handle_info({:enrollment_confirmed, id}, socket) do
    case Enum.split_with(socket.assigns.pending_enrollments, &(&1.enrollment_id == id)) do
      {[_hit], rest} -> {:noreply, assign(socket, :pending_enrollments, rest)}
      {[], _} -> {:noreply, refresh_pending_enrollments(socket)}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp fetch_verification_docs(provider_id) do
    {:ok, docs} = Provider.get_provider_verification_documents(provider_id)
    docs
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
      cover_image_url: p.cover_image_url
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

  # Both invite actions reload the same provider-wide list, so only the
  # InviteActions function varies.
  defp invite_action(action, invite_id, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    action.(socket, invite_id, provider_id, &refresh_outstanding_invites/1)
  end

  defp refresh_outstanding_invites(socket) do
    provider_id = socket.assigns.current_scope.provider.id

    assign(socket, :outstanding_invites, Enrollment.list_outstanding_invites_for_provider(provider_id))
  end

  defp refresh_pending_enrollments(socket) do
    provider = socket.assigns.current_scope.provider

    assign(socket, :pending_enrollments, Enrollment.list_pending_enrollments_for_provider(provider.id))
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
        <.link
          :if={not @identity_verified?}
          id="identity-verify-cta"
          navigate={~p"/provider/verification"}
          class={[
            "flex items-center justify-between gap-3 p-4 border-2 border-amber-300 bg-amber-50",
            Theme.rounded(:xl)
          ]}
        >
          <div class="flex items-start gap-3">
            <.icon name="hero-identification" class="w-6 h-6 text-amber-500 flex-shrink-0 mt-0.5" />
            <div>
              <p class={["font-semibold", Theme.typography(:card_title)]}>
                {gettext("Verify your identity to get approved")}
              </p>
              <p class="text-sm text-gray-500 mt-0.5">
                {gettext("Complete your verification checklist so parents can find and book you.")}
              </p>
            </div>
          </div>
          <.icon name="hero-chevron-right" class="w-5 h-5 text-amber-500 shrink-0" />
        </.link>

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
                class="text-sm font-bold text-[var(--fg-link)]"
              >
                {gettext("Manage")} →
              </.link>
            </div>
            <div :if={@top_programs == []} class="text-sm text-[var(--fg-muted)]">
              {gettext("No programs yet — add your first one from the Programs tab.")}
            </div>
            <div class="space-y-1">
              <.pv_program_row :for={p <- @top_programs} program={p} />
            </div>
          </.kh_card>

          <%!-- Provider-wide, not per-program: the whole point is to see invites nobody
                answered without opening each program's roster in turn (#1073). --%>
          <.kh_card id="outstanding-invites-card" class="p-5">
            <div class="flex items-center justify-between mb-4">
              <h3 class="font-bold text-lg">{gettext("Invitations awaiting a reply")}</h3>
              <span
                id="outstanding-invites-count"
                class="text-xs text-[var(--fg-muted)] font-semibold"
              >
                {length(@outstanding_invites)} {gettext("waiting")}
              </span>
            </div>
            <%!-- Not "outstanding-invites-empty": `invite_table id="outstanding-invites"`
                  in the modal below derives that exact id for its own empty state. --%>
            <div
              :if={@outstanding_invites == []}
              id="outstanding-invites-card-empty"
              class="text-sm text-[var(--fg-muted)]"
            >
              {gettext("Every invitation you sent has been answered.")}
            </div>
            <button
              :if={@outstanding_invites != []}
              id="open-outstanding-invites"
              type="button"
              phx-click="open_invites"
              class={[
                "w-full px-4 py-2 text-sm font-bold border border-hero-grey-300",
                "hover:bg-hero-grey-50 text-left flex items-center justify-between gap-2",
                Theme.rounded(:lg),
                Theme.transition(:normal)
              ]}
            >
              {gettext("Review invitations")}
              <.icon name="hero-chevron-right" class="w-4 h-4 shrink-0" />
            </button>
          </.kh_card>

          <.kh_card id="pending-enrollments-card" class="p-5">
            <div class="flex items-center justify-between mb-4">
              <h3 class="font-bold text-lg">{gettext("Pending enrollments")}</h3>
              <span class="text-xs text-[var(--fg-muted)] font-semibold">
                {length(@pending_enrollments)} {gettext("pending")}
              </span>
            </div>
            <div :if={@pending_enrollments == []} class="text-sm text-[var(--fg-muted)]">
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

      <%!-- Assign-driven rather than URL-param driven, matching `roster_modal/1`:
            the modal is a detail view of state this page already holds, not a
            separately addressable page. --%>
      <div
        :if={@invites_modal_open?}
        id="outstanding-invites-modal"
        class="fixed inset-0 z-50 overflow-y-auto"
        role="dialog"
        aria-modal="true"
        aria-labelledby="outstanding-invites-modal-title"
        phx-window-keydown="close_invites"
        phx-key="Escape"
      >
        <div class="flex min-h-screen items-center justify-center p-4">
          <div class="fixed inset-0 bg-black/50" phx-click="close_invites"></div>
          <div class={["relative bg-white w-full max-w-2xl shadow-xl", Theme.rounded(:xl)]}>
            <div class="flex items-center justify-between p-4 border-b border-hero-grey-200">
              <h3
                id="outstanding-invites-modal-title"
                class="text-lg font-semibold text-hero-black-100"
              >
                {gettext("Invitations awaiting a reply")}
              </h3>
              <button
                id="close-outstanding-invites"
                type="button"
                phx-click="close_invites"
                aria-label={gettext("Close")}
                class={[
                  "p-2 text-[var(--fg-muted)] hover:text-hero-black-100 hover:bg-hero-grey-100",
                  Theme.rounded(:lg),
                  Theme.transition(:normal)
                ]}
              >
                <.icon name="hero-x-mark-mini" class="w-5 h-5" />
              </button>
            </div>
            <div class="p-4">
              <.invite_table
                id="outstanding-invites"
                invites={@outstanding_invites}
                show_program?={true}
                empty_message={gettext("Every invitation you sent has been answered.")}
              />
            </div>
          </div>
        </div>
      </div>
    </.pv_dashboard_shell>
    """
  end
end
