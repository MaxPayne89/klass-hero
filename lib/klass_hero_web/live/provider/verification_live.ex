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

  import KlassHeroWeb.ProviderComponents

  alias KlassHero.Provider
  alias KlassHeroWeb.Presenters.VettingChecklistPresenter
  alias KlassHeroWeb.Provider.Dashboard.Chrome
  alias KlassHeroWeb.Provider.Dashboard.Uploads
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    provider = socket.assigns.current_scope.provider

    if connected?(socket) do
      Phoenix.PubSub.subscribe(KlassHero.PubSub, verification_topic(provider.id))
    end

    all_types = Provider.valid_document_types(provider.entity_type)
    doc_types = all_types |> Enum.reject(&(&1 == "video_screening")) |> Enum.map(&String.to_existing_atom/1)

    socket =
      socket
      |> Chrome.assign()
      |> assign(page_title: gettext("Get verified"))
      |> assign(active_nav: :home)
      |> assign(document_types: doc_types)
      |> assign(doc_type: doc_types |> List.first() |> to_string())
      |> assign(video_upload?: "video_screening" in all_types)
      |> stream(:verification_docs, fetch_verification_docs(provider.id), dom_id: &"vdoc-#{&1.id}")
      |> allow_upload(:verification_doc, accept: ~w(.pdf .jpg .jpeg .png), max_entries: 1, max_file_size: 10_000_000)
      |> allow_upload(:verification_video, accept: ~w(.mp4 .mov .webm), max_entries: 1, max_file_size: 100_000_000)
      |> assign(community_agreement?: Provider.requires_community_agreement?(provider.entity_type))
      |> assign(agreement_form: to_form(%{"agree" => "false"}, as: :agreement))
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
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("select_doc_type", %{"doc_type" => doc_type}, socket) do
    {:noreply, assign(socket, doc_type: doc_type)}
  end

  def handle_event("cancel_upload", %{"ref" => ref, "upload" => upload_name}, socket) do
    {:noreply, cancel_upload(socket, String.to_existing_atom(upload_name), ref)}
  end

  def handle_event("upload_verification_doc", _params, socket) do
    {:noreply, consume_document(socket, :verification_doc, socket.assigns.doc_type)}
  end

  def handle_event("upload_verification_video", _params, socket) do
    {:noreply, consume_document(socket, :verification_video, "video_screening")}
  end

  def handle_event("submit_community_agreement", %{"agreement" => %{"agree" => "true"}}, socket) do
    provider = socket.assigns.current_scope.provider
    signed_by_name = socket.assigns.current_scope.user.name

    case Provider.submit_community_agreement(%{provider_id: provider.id, signed_by_name: signed_by_name}) do
      {:ok, _agreement} ->
        {:noreply,
         socket
         |> assign_verification_state(provider.id)
         |> put_flash(:info, gettext("Thanks — your agreement to the Community Guidelines has been recorded."))}

      {:error, reason} ->
        Logger.error("[VerificationLive.submit_community_agreement] failed",
          provider_id: provider.id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Couldn't record your agreement. Please try again."))}
    end
  end

  def handle_event("submit_community_agreement", _params, socket) do
    {:noreply,
     put_flash(socket, :error, gettext("Please confirm you have read and agree to the Community Guidelines."))}
  end

  @impl true
  def handle_info(:verification_updated, socket) do
    provider_id = socket.assigns.current_scope.provider.id
    {:noreply, assign_verification_state(socket, provider_id)}
  end

  # Consumes one uploaded entry, submits it as a verification document, and streams the
  # new row into the checklist page. Shared by the generic doc uploader and the dedicated
  # video uploader (which pins document_type to "video_screening").
  defp consume_document(socket, upload_key, document_type) do
    provider = socket.assigns.current_scope.provider

    result =
      Uploads.safe_consume_uploaded_entries(socket, upload_key, fn %{path: path}, entry ->
        try do
          # sobelow_skip ["Traversal.FileModule"]
          file_binary = File.read!(path)

          case Provider.submit_verification_document(%{
                 provider_profile_id: provider.id,
                 document_type: document_type,
                 file_binary: file_binary,
                 original_filename: entry.client_name,
                 content_type: entry.client_type
               }) do
            {:ok, doc} -> {:ok, doc}
            {:error, reason} -> {:postpone, reason}
          end
        catch
          kind, reason ->
            Logger.error("[VerificationLive] document upload failed",
              provider_id: provider.id,
              doc_type: document_type,
              kind: kind,
              error: inspect(reason)
            )

            {:error, :upload_exception}
        end
      end)

    case result do
      {:error, :upload_channel_died} ->
        put_flash(socket, :error, gettext("Upload connection lost. Please try again."))

      {:ok, [%{} = doc]} ->
        socket
        |> stream_insert(:verification_docs, doc, dom_id: &"vdoc-#{&1.id}")
        |> put_flash(:info, gettext("Document uploaded successfully."))

      {:ok, other} ->
        Logger.error("[VerificationLive] document upload failed",
          provider_id: provider.id,
          doc_type: document_type,
          errors: inspect(other)
        )

        put_flash(socket, :error, gettext("Failed to upload document."))
    end
  end

  defp fetch_verification_docs(provider_id) do
    {:ok, docs} = Provider.get_provider_verification_documents(provider_id)
    docs
  end

  # Assembles the checklist + identity widget state in one read pass.
  defp assign_verification_state(socket, provider_id) do
    {state, failure_reason} = identity_state(provider_id)

    socket
    |> assign(vetting_checklist: Provider.get_vetting_checklist(provider_id))
    |> assign(identity_state: state, identity_failure_reason: failure_reason)
    |> assign(community_agreement: Provider.get_latest_community_agreement(provider_id))
    |> assign(community_agreement_satisfied?: Provider.community_agreement_satisfied?(provider_id))
    |> assign(community_guidelines_version: Provider.current_community_guidelines_version())
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

      <div class="max-w-xl mx-auto p-4 md:p-6 pt-0">
        <.verification_documents_panel
          verification_docs={@streams.verification_docs}
          uploads={@uploads}
          doc_type={@doc_type}
          document_types={@document_types}
          video_upload?={@video_upload?}
        />
      </div>

      <div :if={@community_agreement?} class="max-w-xl mx-auto p-4 md:p-6 pt-0">
        <.community_agreement_panel
          agreement={@community_agreement}
          satisfied?={@community_agreement_satisfied?}
          version={@community_guidelines_version}
          form={@agreement_form}
        />
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
