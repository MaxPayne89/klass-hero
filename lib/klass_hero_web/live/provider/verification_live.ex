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
  alias Phoenix.HTML.Form

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    provider = socket.assigns.current_scope.provider

    if connected?(socket) do
      Phoenix.PubSub.subscribe(KlassHero.PubSub, verification_topic(provider.id))
    end

    all_types = Provider.valid_document_types(provider.entity_type)
    # video_screening and business_registration have dedicated widgets, so they are excluded from
    # the generic document-upload select (a step must be submittable via exactly one surface).
    generic_excluded = ~w(video_screening business_registration)
    doc_types = all_types |> Enum.reject(&(&1 in generic_excluded)) |> Enum.map(&String.to_existing_atom/1)

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
      |> allow_upload(:business_registration_doc,
        accept: ~w(.pdf .jpg .jpeg .png),
        max_entries: 1,
        max_file_size: 10_000_000
      )
      |> assign(community_agreement?: Provider.requires_community_agreement?(provider.entity_type))
      |> assign(agreement_form: to_form(%{"agree" => "false"}, as: :agreement))
      |> assign(responsible_person_form: responsible_person_form(provider))
      |> assign(business_registration_form: business_registration_form(provider))
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

  def handle_event("start_responsible_person_verification", %{"responsible_person" => params}, socket) do
    provider_id = socket.assigns.current_scope.provider.id
    return_url = url(~p"/provider/verification")
    name = Map.get(params, "name", "")
    role = Map.get(params, "role", "")

    case Provider.start_responsible_person_verification(provider_id, name, role, return_url) do
      {:ok, %{redirect_url: redirect_url, change: change}} ->
        {:noreply, socket |> maybe_flash_reset(change) |> redirect(external: redirect_url)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, gettext("Please enter the responsible person's full name and role."))}

      {:error, reason} ->
        Logger.error("[VerificationLive.start_responsible_person_verification] failed",
          provider_id: provider_id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Couldn't start identity verification. Please try again."))}
    end
  end

  def handle_event("submit_business_registration", %{"business_registration" => params}, socket) do
    provider = socket.assigns.current_scope.provider

    if Enum.empty?(socket.assigns.uploads.business_registration_doc.entries) do
      {:noreply,
       socket
       |> assign(business_registration_form: to_form(params, as: :business_registration))
       |> put_flash(:error, gettext("Please attach your registration document."))}
    else
      {:noreply, consume_business_registration(socket, provider, params)}
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
    agreement = Provider.get_latest_community_agreement(provider_id)

    socket
    |> assign(vetting_checklist: Provider.get_vetting_checklist(provider_id))
    |> assign(identity_state: state, identity_failure_reason: failure_reason)
    |> assign(community_agreement: agreement)
    |> assign(community_agreement_satisfied?: Provider.community_agreement_satisfied?(agreement))
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
                  <% row.action_kind == :responsible_person -> %>
                    <.responsible_person_widget
                      identity_state={@identity_state}
                      failure_reason={@identity_failure_reason}
                      form={@responsible_person_form}
                    />
                  <% row.action_kind == :business_registration -> %>
                    <.business_registration_widget
                      form={@business_registration_form}
                      uploads={@uploads}
                      ui_status={row.ui_status}
                      rejection_reason={row.rejection_reason}
                    />
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

  # Pre-fills the responsible-person form from the provider's stored value (blank on first visit).
  defp responsible_person_form(provider) do
    to_form(
      %{"name" => provider.responsible_person_name || "", "role" => provider.responsible_person_role || ""},
      as: :responsible_person
    )
  end

  # A genuine change reset identity + the two agreements, so tell the provider to re-verify.
  defp maybe_flash_reset(socket, :changed) do
    put_flash(socket, :info, gettext("Responsible person updated — please re-verify their identity."))
  end

  defp maybe_flash_reset(socket, _change), do: socket

  attr :identity_state, :atom, required: true
  attr :failure_reason, :string, default: nil
  attr :form, Form, required: true

  # The single business-identity surface (ADR-0010): captures the Responsible Person's name/role
  # and starts their Stripe session. Editing the name and resubmitting IS the change flow — always
  # available, in any lifecycle, so a director who leaves after approval can be replaced.
  defp responsible_person_widget(assigns) do
    ~H"""
    <div id="responsible-person" class={[Theme.card_variant(:default), "p-4 md:p-6"]}>
      <%= case @identity_state do %>
        <% :in_progress -> %>
          <p id="responsible-person-in-progress" class={["mb-4 text-sm", Theme.text_color(:body)]}>
            {gettext("Verifying the responsible person's identity… this can take a moment.")}
          </p>
        <% :approved -> %>
          <div id="responsible-person-approved" class="mb-4 flex items-center gap-2">
            <.icon name="hero-check-circle-solid" class="w-6 h-6 text-green-600" />
            <p class={["text-sm font-medium", Theme.text_color(:body)]}>
              {gettext("The responsible person's identity is verified.")}
            </p>
          </div>
        <% :failed -> %>
          <p id="responsible-person-failed" class="mb-4 text-sm text-red-700">
            {failure_reason_message(@failure_reason)}
          </p>
        <% _ -> %>
      <% end %>

      <p class={["mb-4 text-sm", Theme.text_color(:muted)]}>
        {gettext(
          "Enter the owner or director legally accountable for the business. They verify their identity with our partner Stripe. Changing this person restarts the identity and agreement steps."
        )}
      </p>

      <.form
        for={@form}
        id="responsible-person-form"
        phx-submit="start_responsible_person_verification"
      >
        <.input field={@form[:name]} type="text" label={gettext("Responsible person's full name")} />
        <.input field={@form[:role]} type="text" label={gettext("Role (e.g. Owner, Director)")} />
        <.button id="responsible-person-start" class="mt-2">
          {responsible_person_button_label(@identity_state)}
        </.button>
      </.form>
    </div>
    """
  end

  defp responsible_person_button_label(:not_started), do: gettext("Verify identity")
  defp responsible_person_button_label(_state), do: gettext("Update & re-verify")

  # Pre-fills the registration form from the provider's stored values (blank on first visit).
  defp business_registration_form(provider) do
    to_form(
      %{
        "legal_business_name" => provider.legal_business_name || "",
        "registration_number" => provider.registration_number || "",
        "registration_country" => provider.registration_country || ""
      },
      as: :business_registration
    )
  end

  # Consumes the uploaded registration document and submits it with the three structured fields in
  # one atomic command (Provider.submit_business_registration/2). On success re-derives the checklist
  # so the step badge flips to "Under review"; the typed values are echoed back into the form.
  defp consume_business_registration(socket, provider, params) do
    fields = %{
      legal_business_name: Map.get(params, "legal_business_name", ""),
      registration_number: Map.get(params, "registration_number", ""),
      registration_country: Map.get(params, "registration_country", "")
    }

    result =
      Uploads.safe_consume_uploaded_entries(socket, :business_registration_doc, fn %{path: path}, entry ->
        try do
          # sobelow_skip ["Traversal.FileModule"]
          file_binary = File.read!(path)

          attrs =
            Map.merge(fields, %{
              file_binary: file_binary,
              original_filename: entry.client_name,
              content_type: entry.client_type
            })

          case Provider.submit_business_registration(provider.id, attrs) do
            {:ok, doc} -> {:ok, doc}
            {:error, reason} -> {:postpone, reason}
          end
        catch
          kind, reason ->
            Logger.error("[VerificationLive] business registration submit failed",
              provider_id: provider.id,
              kind: kind,
              error: inspect(reason)
            )

            {:error, :upload_exception}
        end
      end)

    socket = assign(socket, business_registration_form: to_form(params, as: :business_registration))

    case result do
      {:error, :upload_channel_died} ->
        put_flash(socket, :error, gettext("Upload connection lost. Please try again."))

      {:ok, [%{} = doc]} ->
        socket
        |> stream_insert(:verification_docs, doc, dom_id: &"vdoc-#{&1.id}")
        |> assign_verification_state(provider.id)
        |> put_flash(:info, gettext("Business registration submitted for review."))

      # A non-empty upload that produced no document was postponed by the command — the
      # structured fields failed validation (empty-upload is handled before we get here).
      {:ok, _} ->
        put_flash(socket, :error, gettext("Please enter your legal business name, registration number and country."))
    end
  end

  # Curated country options for the <select>. The set of codes is single-sourced from the domain
  # (Provider.registration_countries/0, the same list business_registration_changeset validates
  # against, ADR-0011), so the UI and the changeset can never desync; only the labels live here.
  defp country_options do
    Enum.map(Provider.registration_countries(), &{country_label(&1), &1})
  end

  defp country_label("DE"), do: gettext("Germany")
  defp country_label("GB"), do: gettext("United Kingdom")
  defp country_label("OTHER"), do: gettext("Other")

  defp registration_guidance("DE"), do: gettext("Germany: your Gewerbeanmeldung or Handelsregisterauszug.")
  defp registration_guidance("GB"), do: gettext("United Kingdom: your Companies House certificate.")

  defp registration_guidance("OTHER"), do: gettext("Other: your equivalent national business registration document.")

  defp registration_guidance(_), do: gettext("Select your country to see which document to upload.")

  attr :form, Form, required: true
  attr :uploads, :map, required: true
  attr :ui_status, :atom, required: true
  attr :rejection_reason, :string, default: nil

  # The single business-registration surface (B2): captures the structured registration facts and
  # the document in one submit. The form stays available in every state (the banner shows progress),
  # so a business can resubmit a corrected document after a rejection.
  defp business_registration_widget(assigns) do
    ~H"""
    <div id="business-registration" class={[Theme.card_variant(:default), "p-4 md:p-6"]}>
      <%= case @ui_status do %>
        <% :submitted -> %>
          <p id="business-registration-submitted" class={["mb-4 text-sm", Theme.text_color(:body)]}>
            {gettext("Your registration document is under review.")}
          </p>
        <% :approved -> %>
          <div id="business-registration-approved" class="mb-4 flex items-center gap-2">
            <.icon name="hero-check-circle-solid" class="w-6 h-6 text-green-600" />
            <p class={["text-sm font-medium", Theme.text_color(:body)]}>
              {gettext("Your business registration is verified.")}
            </p>
          </div>
        <% :rejected -> %>
          <p id="business-registration-rejected" class="mb-4 text-sm text-red-700">
            {@rejection_reason}
          </p>
        <% _ -> %>
      <% end %>

      <p class={["mb-4 text-sm", Theme.text_color(:muted)]}>
        {gettext(
          "Upload proof that your business is legally registered. Choose your country of registration for guidance on which document we need."
        )}
      </p>

      <.form
        for={@form}
        id="business-registration-form"
        phx-submit="submit_business_registration"
        phx-change="validate_upload"
      >
        <.input
          field={@form[:registration_country]}
          type="select"
          label={gettext("Country of registration")}
          options={country_options()}
        />
        <p class={["mt-1 mb-3", Theme.typography(:caption)]}>
          {registration_guidance(@form[:registration_country].value)}
        </p>
        <.input
          field={@form[:legal_business_name]}
          type="text"
          label={gettext("Legal business name")}
        />
        <.input
          field={@form[:registration_number]}
          type="text"
          label={gettext("Registration number")}
        />

        <.live_file_input upload={@uploads.business_registration_doc} class="mt-2 block" />
        <p class={["mt-1", Theme.typography(:caption)]}>{gettext("PDF, JPG or PNG. Max 10MB.")}</p>

        <.button id="business-registration-submit" class="mt-3">{gettext("Submit for review")}</.button>
      </.form>
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
