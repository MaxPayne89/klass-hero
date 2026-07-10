defmodule KlassHeroWeb.Provider.VerificationLive do
  @moduledoc """
  Provider "Get verified" page: the onboarding vetting checklist plus the inline Stripe
  Identity widget. A fresh, self-contained route-level LiveView (the old monolithic
  `DashboardLive` `:verification` action was split out by #904).

  Live refresh is provider-scoped: the step-engine handlers broadcast
  `"provider:<id>:verification_updated"` after they recompute the case (on a document review
  or a Stripe Identity webhook), and this view re-fetches on that one signal — the DB row is
  the source of truth, never the event payload.
  """
  use KlassHeroWeb, :live_view

  alias KlassHero.Provider
  alias KlassHeroWeb.Presenters.VettingChecklistPresenter
  alias KlassHeroWeb.Provider.Dashboard.Chrome
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    provider = socket.assigns.current_scope.provider

    if connected?(socket) do
      Phoenix.PubSub.subscribe(KlassHero.PubSub, verification_topic(provider.id))
    end

    socket =
      socket
      |> Chrome.assign()
      |> assign(page_title: gettext("Get verified"))
      |> assign(active_nav: :home)
      |> assign_verification_state(provider.id)

    {:ok, socket}
  end

  @impl true
  def handle_event("start_identity_verification", _params, socket) do
    provider_id = socket.assigns.current_scope.provider.id
    return_url = url(~p"/provider/verification")

    case Provider.create_identity_verification_session(provider_id, return_url) do
      {:ok, %{redirect_url: redirect_url}} ->
        {:noreply, redirect(socket, external: redirect_url)}

      {:error, reason} ->
        Logger.error("[VerificationLive.start_identity_verification] failed",
          provider_id: provider_id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Couldn't start identity verification. Please try again."))}
    end
  end

  @impl true
  def handle_info(:verification_updated, socket) do
    provider_id = socket.assigns.current_scope.provider.id
    {:noreply, assign_verification_state(socket, provider_id)}
  end

  # Assembles the checklist + identity widget state in one read pass.
  defp assign_verification_state(socket, provider_id) do
    {state, failure_reason} = identity_state(provider_id)

    socket
    |> assign(vetting_checklist: Provider.get_vetting_checklist(provider_id))
    |> assign(identity_state: state, identity_failure_reason: failure_reason)
  end

  # Derives the 4-state widget status from the latest identity record. Once a session leaves
  # `:processing`, `outcome` is always populated, so requires_input/canceled/under_18/
  # age_unverifiable all surface as `:failed`, distinguished by `failure_reason` copy.
  defp identity_state(provider_id) do
    case Provider.get_latest_identity_verification(provider_id) do
      {:error, :not_found} -> {:not_started, nil}
      {:ok, %{status: :processing}} -> {:in_progress, nil}
      {:ok, %{outcome: :pass}} -> {:approved, nil}
      {:ok, %{outcome: :fail, failure_reason: reason}} -> {:failed, reason}
    end
  end

  defp verification_topic(provider_id), do: "provider:#{provider_id}:verification_updated"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :rows, VettingChecklistPresenter.rows(assigns.vetting_checklist))

    ~H"""
    <div class={["min-h-screen", Theme.bg(:muted)]}>
      <div id="vetting-checklist" class="max-w-xl mx-auto p-4 md:p-6">
        <h2 class={[Theme.typography(:section_title), Theme.text_color(:heading), "mb-2"]}>
          {gettext("Get verified")}
        </h2>

        <div
          :if={not @vetting_checklist.verified?}
          id="vetting-locked-banner"
          class={["flex items-start gap-3 p-4 mb-4", Theme.rounded(:lg), Theme.status(:info)]}
        >
          <.icon name="hero-lock-closed" class="w-5 h-5 mt-0.5 shrink-0" />
          <div>
            <p class={Theme.typography(:card_title)}>{gettext("Profile locked")}</p>
            <p class={Theme.typography(:body_small)}>
              {VettingChecklistPresenter.locked_summary(@vetting_checklist)}
            </p>
          </div>
        </div>

        <ul class="space-y-3">
          <li :for={row <- @rows} id={"vetting-step-#{row.key}"}>
            <.kh_list_row class="border border-hero-grey-200">
              <:media>
                <.kh_icon_chip icon={row.icon} gradient={row.gradient} size={:md} />
              </:media>
              <:title>{row.title}</:title>
              <:pill>
                <.kh_pill tone={row.badge_tone}>{row.badge_label}</.kh_pill>
              </:pill>
              <:actions>
                <%= case row.action_kind do %>
                  <% :navigate_documents -> %>
                    <.link
                      id={"vetting-action-#{row.key}"}
                      href="#verification-docs"
                      class={[
                        "inline-flex items-center px-3 py-1.5 text-sm font-semibold",
                        Theme.rounded(:md),
                        Theme.button_variant(:outline)
                      ]}
                    >
                      {row.action_label}
                    </.link>
                  <% :navigate_agreement -> %>
                    <.link
                      id={"vetting-action-#{row.key}"}
                      href="#community-agreement-form"
                      class={[
                        "inline-flex items-center px-3 py-1.5 text-sm font-semibold",
                        Theme.rounded(:md),
                        Theme.button_variant(:outline)
                      ]}
                    >
                      {row.action_label}
                    </.link>
                  <% _ -> %>
                <% end %>
              </:actions>
              <:footer>
                <%= cond do %>
                  <% row.action_kind == :identity -> %>
                    <.identity_state_widget
                      identity_state={@identity_state}
                      failure_reason={@identity_failure_reason}
                    />
                  <% row.ui_status == :rejected and row.rejection_reason -> %>
                    <p class={["text-red-700", Theme.typography(:body_small)]}>
                      {row.rejection_reason}
                    </p>
                  <% true -> %>
                <% end %>
              </:footer>
            </.kh_list_row>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  attr :identity_state, :atom, required: true
  attr :failure_reason, :string, default: nil

  defp identity_state_widget(assigns) do
    ~H"""
    <div id="identity-verification">
      <%= case @identity_state do %>
        <% :not_started -> %>
          <div id="identity-verify-not-started" class={[Theme.card_variant(:default), "p-4 md:p-6"]}>
            <p class={["mb-4 text-sm", Theme.text_color(:muted)]}>
              {gettext(
                "Verify your identity with our partner Stripe to get approved. You'll be sent to a secure page and brought back here."
              )}
            </p>
            <.button id="identity-verify-start" phx-click="start_identity_verification">
              {gettext("Verify identity")}
            </.button>
            <p class={["mt-3", Theme.typography(:caption)]}>
              {gettext("Takes about 2 minutes. Once verified, your provider account can be approved.")}
            </p>
          </div>
        <% :in_progress -> %>
          <div id="identity-verify-in-progress" class={[Theme.card_variant(:default), "p-4 md:p-6"]}>
            <p class={["text-sm", Theme.text_color(:body)]}>
              {gettext("Verifying your identity… this can take a moment.")}
            </p>
          </div>
        <% :approved -> %>
          <div
            id="identity-verify-approved"
            class={[Theme.card_variant(:default), "p-4 md:p-6 flex items-center gap-2"]}
          >
            <.icon name="hero-check-circle-solid" class="w-6 h-6 text-green-600" />
            <p class={["text-sm font-medium", Theme.text_color(:body)]}>
              {gettext("Your identity is verified.")}
            </p>
          </div>
        <% :failed -> %>
          <div id="identity-verify-failed" class={[Theme.card_variant(:default), "p-4 md:p-6"]}>
            <p class="mb-4 text-sm text-red-700">{failure_reason_message(@failure_reason)}</p>
            <.button id="identity-verify-retry" phx-click="start_identity_verification">
              {gettext("Retry verification")}
            </.button>
          </div>
      <% end %>
    </div>
    """
  end

  # Maps a Stripe Identity failure_reason to provider-facing copy on the failed state.
  # "under_18" is terminal (Klass Hero is 18+); the rest are retryable, so the wording invites it.
  defp failure_reason_message("under_18"),
    do: gettext("Klass Hero is only open to providers aged 18 and over, so we can't approve this account.")

  defp failure_reason_message("age_unverifiable"),
    do:
      gettext("We couldn't read your date of birth from your ID. A clearer photo of your document should do the trick.")

  defp failure_reason_message("requires_input"),
    do: gettext("Something tripped up the check — usually a blurry photo. Give it another go.")

  defp failure_reason_message("canceled"),
    do: gettext("Looks like the check didn't finish. Pick up where you left off whenever you're ready.")

  defp failure_reason_message(_reason), do: gettext("We couldn't verify your identity. Please try again.")
end
