defmodule KlassHeroWeb.Admin.VerificationsLive do
  @moduledoc """
  LiveView for admin verification document management.

  Supports two actions:
  - `:index` - Lists verification documents with status filtering (all/pending/approved/rejected)
  - `:show` - Document detail page with preview, approve, and reject workflows

  Supports URL-based filtering via query params for bookmarkable views.
  """

  use KlassHeroWeb, :live_view

  import KlassHeroWeb.ProviderComponents

  alias KlassHero.Provider
  alias KlassHero.Provider.VerificationDocument
  alias KlassHeroWeb.Presenters.ProviderPresenter
  alias KlassHeroWeb.Theme

  require Logger

  @valid_statuses ~w(pending approved rejected)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    status = parse_status_filter(params)

    {:ok, results} = Provider.list_verification_documents_for_admin(status)
    {:ok, identity_verifications} = Provider.list_identity_verifications_for_admin()

    socket
    |> assign(:page_title, gettext("Verifications"))
    |> assign(:current_status, status)
    |> assign(:document_count, length(results))
    |> assign(:identity_verifications, identity_verifications)
    |> stream(:documents, results,
      reset: true,
      dom_id: fn %{document: doc} -> "doc-#{doc.id}" end
    )
  end

  # Non-UUID strings cause Ecto.Query.CastError — redirect instead of crashing.
  defp apply_action(socket, :show, %{"id" => id}) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        apply_show_action(socket, uuid)

      :error ->
        socket
        |> put_flash(:error, gettext("Verification document not found."))
        |> push_navigate(to: ~p"/admin/verifications")
    end
  end

  defp apply_show_action(socket, id) do
    case Provider.get_verification_document_preview(id) do
      {:ok, result} ->
        socket
        |> assign(
          :page_title,
          ProviderPresenter.document_type_label(result.document.document_type)
        )
        |> assign(:document, result.document)
        |> assign(:provider_business_name, result.provider_business_name)
        |> assign(:legal_business_name, result.legal_business_name)
        |> assign(:registration_number, result.registration_number)
        |> assign(:signed_url, result.signed_url)
        |> assign(:preview_type, result.preview_type)
        |> assign(:show_reject_form, false)
        |> assign(:reject_form, to_form(%{"reason" => ""}, as: :rejection))

      {:error, :not_found} ->
        socket
        |> put_flash(:error, gettext("Verification document not found."))
        |> push_navigate(to: ~p"/admin/verifications")
    end
  end

  defp parse_status_filter(%{"status" => status}) when status in @valid_statuses do
    String.to_existing_atom(status)
  end

  defp parse_status_filter(_params), do: nil

  @impl true
  def handle_event("approve", _params, socket) do
    document = socket.assigns.document
    reviewer_id = socket.assigns.current_scope.user.id

    case Provider.approve_verification_document(document.id, reviewer_id) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:document, updated)
         |> put_flash(:info, gettext("Document approved successfully."))}

      {:error, :document_not_pending} ->
        {:noreply, put_flash(socket, :error, gettext("Document has already been reviewed."))}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Verification document not found."))
         |> push_navigate(to: ~p"/admin/verifications")}

      {:error, reason} ->
        Logger.error("Failed to approve verification document",
          document_id: document.id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Failed to approve document."))}
    end
  end

  @impl true
  def handle_event("validate_rejection", %{"rejection" => params}, socket) do
    {:noreply, assign(socket, :reject_form, to_form(params, as: :rejection))}
  end

  @impl true
  def handle_event("toggle_reject_form", _params, socket) do
    {:noreply, assign(socket, :show_reject_form, !socket.assigns.show_reject_form)}
  end

  @impl true
  def handle_event("reject", %{"rejection" => %{"reason" => reason}}, socket) do
    document = socket.assigns.document
    reviewer_id = socket.assigns.current_scope.user.id

    case Provider.reject_verification_document(document.id, reviewer_id, reason) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:document, updated)
         |> assign(:show_reject_form, false)
         |> put_flash(:info, gettext("Document rejected."))}

      {:error, :reason_required} ->
        {:noreply, put_flash(socket, :error, gettext("Please provide a rejection reason."))}

      {:error, :document_not_pending} ->
        {:noreply, put_flash(socket, :error, gettext("Document has already been reviewed."))}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Verification document not found."))
         |> push_navigate(to: ~p"/admin/verifications")}

      {:error, reason} ->
        Logger.error("Failed to reject verification document",
          document_id: document.id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Failed to reject document."))}
    end
  end

  @impl true
  def render(assigns) do
    render_action(assigns)
  end

  defp render_action(%{live_action: :index} = assigns) do
    ~H"""
    <div class="min-h-screen p-4 md:p-6">
      <%!-- Header --%>
      <div class="mb-6">
        <h1 class={[Theme.typography(:section_title), Theme.text_color(:heading)]}>
          {gettext("Verifications")}
        </h1>
        <p class={["mt-1", Theme.typography(:body_small), Theme.text_color(:muted)]}>
          {ngettext(
            "%{count} document",
            "%{count} documents",
            @document_count,
            count: @document_count
          )}
        </p>
      </div>

      <%!-- Filter Tabs --%>
      <nav id="verification-filters" class="flex gap-2 mb-6 overflow-x-auto pb-2">
        <.filter_tab
          label={gettext("All")}
          status={nil}
          current_status={@current_status}
        />
        <.filter_tab
          label={gettext("Pending")}
          status={:pending}
          current_status={@current_status}
        />
        <.filter_tab
          label={gettext("Approved")}
          status={:approved}
          current_status={@current_status}
        />
        <.filter_tab
          label={gettext("Rejected")}
          status={:rejected}
          current_status={@current_status}
        />
      </nav>

      <%!-- Document List --%>
      <div id="documents" phx-update="stream" class="space-y-3">
        <div id="documents-empty" class="hidden only:block">
          <.documents_empty_state current_status={@current_status} />
        </div>

        <.link
          :for={{dom_id, entry} <- @streams.documents}
          id={dom_id}
          navigate={~p"/admin/verifications/#{entry.document.id}"}
          class={[
            Theme.card_variant(:default),
            "block p-4 hover:bg-gray-50 transition-colors"
          ]}
        >
          <% reg_no? =
            entry.document.document_type == :business_registration and entry.registration_number %>
          <%!-- Mobile: stacked card layout --%>
          <div class="md:hidden space-y-2">
            <div class="flex items-center justify-between">
              <span class="font-semibold text-sm truncate mr-2">
                {entry.provider_business_name}
              </span>
              <.doc_status_badge status={entry.document.status} />
            </div>
            <p class={["text-sm", Theme.text_color(:body)]}>
              {ProviderPresenter.document_type_label(entry.document.document_type)}
            </p>
            <p :if={reg_no?} class={["text-xs", Theme.text_color(:muted)]}>
              {gettext("Reg. no.")}: {entry.registration_number}
            </p>
            <div class="flex items-center justify-between">
              <span class={["text-xs truncate mr-2", Theme.text_color(:muted)]}>
                {entry.document.original_filename}
              </span>
              <span class={["text-xs whitespace-nowrap", Theme.text_color(:muted)]}>
                {format_date(entry.document.inserted_at)}
              </span>
            </div>
          </div>

          <%!-- Desktop: row layout --%>
          <div class="hidden md:grid md:grid-cols-12 md:gap-4 md:items-center">
            <div class="col-span-3 min-w-0">
              <span class="font-semibold text-sm truncate block">
                {entry.provider_business_name}
              </span>
              <span :if={reg_no?} class={["text-xs truncate block", Theme.text_color(:muted)]}>
                {gettext("Reg. no.")}: {entry.registration_number}
              </span>
            </div>
            <span class={["col-span-3 text-sm", Theme.text_color(:body)]}>
              {ProviderPresenter.document_type_label(entry.document.document_type)}
            </span>
            <div class="col-span-2">
              <.doc_status_badge status={entry.document.status} />
            </div>
            <span class={["col-span-2 text-sm truncate", Theme.text_color(:muted)]}>
              {entry.document.original_filename}
            </span>
            <span class={["col-span-2 text-sm text-right", Theme.text_color(:muted)]}>
              {format_date(entry.document.inserted_at)}
            </span>
          </div>
        </.link>
      </div>

      <%!-- Identity verifications (read-only — Stripe Identity outcomes, no manual review) --%>
      <section id="identity-verifications-section" class="mt-10">
        <h2 class={[Theme.typography(:card_title), Theme.text_color(:heading), "mb-3"]}>
          {gettext("Identity verifications")}
        </h2>

        <div :if={@identity_verifications == []} class={["p-4 text-sm", Theme.text_color(:muted)]}>
          {gettext("No identity verifications yet.")}
        </div>

        <div class="space-y-3">
          <div
            :for={entry <- @identity_verifications}
            id={"identity-verification-#{entry.identity_verification.id}"}
            class={[Theme.card_variant(:default), "p-4"]}
          >
            <div class="flex items-center justify-between gap-2">
              <span class="font-semibold text-sm truncate">{entry.provider_business_name}</span>
              <.identity_status_badge
                status={entry.identity_verification.status}
                outcome={entry.identity_verification.outcome}
              />
            </div>
            <p
              :if={entry.identity_verification.failure_reason}
              class={["mt-1 text-xs", Theme.text_color(:muted)]}
            >
              {entry.identity_verification.failure_reason}
            </p>
          </div>
        </div>
      </section>
    </div>
    """
  end

  defp render_action(%{live_action: :show} = assigns) do
    ~H"""
    <div class="min-h-screen p-4 md:p-6 max-w-4xl mx-auto">
      <%!-- Back link --%>
      <.link
        navigate={~p"/admin/verifications"}
        class={[
          "inline-flex items-center gap-1 mb-6 text-sm",
          Theme.text_color(:muted),
          "hover:text-gray-900"
        ]}
      >
        <.icon name="hero-arrow-left-mini" class="w-4 h-4" />
        {gettext("Back to verifications")}
      </.link>

      <%!-- Header --%>
      <div class="flex items-center justify-between mb-6">
        <h1 class={[Theme.typography(:section_title), Theme.text_color(:heading)]}>
          {ProviderPresenter.document_type_label(@document.document_type)}
        </h1>
        <.doc_status_badge status={@document.status} />
      </div>

      <%!-- Info grid --%>
      <div id="document-info" class={[Theme.card_variant(:default), "p-4 md:p-6 mb-6"]}>
        <% business_reg? = @document.document_type == :business_registration %>
        <dl class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <dt class={["text-sm font-medium", Theme.text_color(:muted)]}>{gettext("Business")}</dt>
            <dd class="mt-1 text-sm">{@provider_business_name}</dd>
          </div>
          <div :if={business_reg?}>
            <dt class={["text-sm font-medium", Theme.text_color(:muted)]}>
              {gettext("Legal business name")}
            </dt>
            <dd class="mt-1 text-sm">{@legal_business_name}</dd>
          </div>
          <div :if={business_reg?}>
            <dt class={["text-sm font-medium", Theme.text_color(:muted)]}>
              {gettext("Registration number")}
            </dt>
            <dd class="mt-1 text-sm">{@registration_number}</dd>
          </div>
          <div :if={@document.expiry_date} id="document-expiry">
            <dt class={["text-sm font-medium", Theme.text_color(:muted)]}>
              {gettext("Policy expiry")}
            </dt>
            <dd class="mt-1 text-sm flex items-center gap-2">
              {format_date(@document.expiry_date)}
              <% exp = VerificationDocument.expiry_status(@document, Date.utc_today()) %>
              <.kh_pill tone={expiry_tone(exp)}>{expiry_badge_label(exp)}</.kh_pill>
            </dd>
          </div>
          <div>
            <dt class={["text-sm font-medium", Theme.text_color(:muted)]}>{gettext("File")}</dt>
            <dd class="mt-1 text-sm truncate">{@document.original_filename}</dd>
          </div>
          <div>
            <dt class={["text-sm font-medium", Theme.text_color(:muted)]}>{gettext("Submitted")}</dt>
            <dd class="mt-1 text-sm">{format_date(@document.inserted_at)}</dd>
          </div>
          <%= if @document.reviewed_at do %>
            <div>
              <dt class={["text-sm font-medium", Theme.text_color(:muted)]}>{gettext("Reviewed")}</dt>
              <dd class="mt-1 text-sm">{format_date(@document.reviewed_at)}</dd>
            </div>
          <% end %>
        </dl>

        <%!-- Rejection reason (shown only for rejected documents) --%>
        <%= if @document.status == :rejected && @document.rejection_reason do %>
          <div id="rejection-reason" class="mt-4 p-3 bg-red-50 border border-red-200 rounded-lg">
            <p class="text-sm font-medium text-red-800">{gettext("Rejection reason")}</p>
            <p class="mt-1 text-sm text-red-700">{@document.rejection_reason}</p>
          </div>
        <% end %>
      </div>

      <%!-- Document preview --%>
      <div id="document-preview" class={[Theme.card_variant(:default), "p-4 md:p-6 mb-6"]}>
        <h2 class={["text-sm font-medium mb-4", Theme.text_color(:muted)]}>
          {gettext("Document preview")}
        </h2>

        <%= if @signed_url do %>
          <.document_viewer preview_type={@preview_type} signed_url={@signed_url} />
          <div class="mt-3">
            <a
              href={@signed_url}
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1 text-sm text-blue-600 hover:text-blue-800"
            >
              <.icon name="hero-arrow-down-tray-mini" class="w-4 h-4" />
              {gettext("Download document")}
            </a>
          </div>
        <% else %>
          <div class="text-center py-8">
            <.icon
              name="hero-exclamation-triangle"
              class={"w-8 h-8 mx-auto mb-2 #{Theme.text_color(:muted)}"}
            />
            <p class={["text-sm", Theme.text_color(:muted)]}>
              {gettext("Unable to load document preview.")}
            </p>
          </div>
        <% end %>
      </div>

      <%!-- Action buttons (pending only) --%>
      <%= if @document.status == :pending do %>
        <div id="review-actions" class={[Theme.card_variant(:default), "p-4 md:p-6"]}>
          <div class="flex gap-3">
            <button
              id="approve-button"
              phx-click="approve"
              data-confirm={gettext("Are you sure you want to approve this document?")}
              class="inline-flex items-center px-4 py-2 bg-green-600 text-white text-sm font-medium rounded-lg hover:bg-green-700 transition-colors"
            >
              <.icon name="hero-check-mini" class="w-4 h-4 mr-1" />
              {gettext("Approve")}
            </button>
            <button
              id="reject-button"
              phx-click="toggle_reject_form"
              class="inline-flex items-center px-4 py-2 bg-red-600 text-white text-sm font-medium rounded-lg hover:bg-red-700 transition-colors"
            >
              <.icon name="hero-x-mark-mini" class="w-4 h-4 mr-1" />
              {gettext("Reject")}
            </button>
          </div>

          <%!-- Rejection form (toggled by Reject button) --%>
          <%= if @show_reject_form do %>
            <.form
              for={@reject_form}
              id="reject-form"
              phx-change="validate_rejection"
              phx-submit="reject"
              class="mt-4"
            >
              <.input
                field={@reject_form[:reason]}
                type="textarea"
                label={gettext("Rejection reason")}
                required
                rows="3"
                placeholder={gettext("Explain why this document is being rejected...")}
              />
              <div class="flex gap-3 mt-3">
                <button
                  id="confirm-reject-button"
                  type="submit"
                  class="inline-flex items-center px-4 py-2 bg-red-600 text-white text-sm font-medium rounded-lg hover:bg-red-700 transition-colors"
                >
                  {gettext("Confirm rejection")}
                </button>
                <button
                  type="button"
                  phx-click="toggle_reject_form"
                  class={[
                    "px-4 py-2 text-sm font-medium rounded-lg",
                    Theme.text_color(:muted),
                    "hover:bg-gray-100 transition-colors"
                  ]}
                >
                  {gettext("Cancel")}
                </button>
              </div>
            </.form>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :status, :atom, required: true
  attr :current_status, :atom, required: true

  defp filter_tab(assigns) do
    ~H"""
    <.link
      patch={filter_path(@status)}
      class={[
        "px-4 py-2 rounded-full text-sm font-medium whitespace-nowrap transition-colors",
        if(@status == @current_status,
          do: [Theme.bg(:primary), "text-white"],
          else: [Theme.bg(:surface), Theme.text_color(:muted), "hover:bg-gray-100"]
        )
      ]}
    >
      {@label}
    </.link>
    """
  end

  attr :current_status, :atom, required: true

  defp documents_empty_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <.icon
        name="hero-document-magnifying-glass"
        class={"w-12 h-12 mx-auto mb-4 #{Theme.text_color(:muted)}"}
      />
      <p class={[Theme.typography(:body), Theme.text_color(:muted)]}>
        {empty_message(@current_status)}
      </p>
    </div>
    """
  end

  attr :preview_type, :atom, required: true
  attr :signed_url, :string, required: true

  defp document_viewer(%{preview_type: :image} = assigns) do
    ~H"""
    <a href={@signed_url} target="_blank" rel="noopener noreferrer">
      <img
        src={@signed_url}
        alt={gettext("Document preview")}
        class="max-w-full max-h-[600px] rounded-lg border border-gray-200"
      />
    </a>
    """
  end

  defp document_viewer(%{preview_type: :pdf} = assigns) do
    ~H"""
    <iframe
      src={@signed_url}
      class="w-full h-[600px] rounded-lg border border-gray-200"
      title={gettext("Document preview")}
    ></iframe>
    """
  end

  defp document_viewer(%{preview_type: :video} = assigns) do
    ~H"""
    <video src={@signed_url} controls class="w-full max-h-[600px] rounded-lg border border-gray-200">
      {gettext("Your browser does not support video playback.")}
    </video>
    """
  end

  defp document_viewer(assigns) do
    ~H"""
    <div class="text-center py-8">
      <.icon name="hero-document" class={"w-12 h-12 mx-auto mb-2 #{Theme.text_color(:muted)}"} />
      <p class={["text-sm", Theme.text_color(:muted)]}>
        {gettext("Preview not available for this file type.")}
      </p>
    </div>
    """
  end

  defp filter_path(nil), do: ~p"/admin/verifications"
  defp filter_path(status), do: ~p"/admin/verifications?status=#{status}"

  defp empty_message(nil), do: gettext("No verification documents found.")
  defp empty_message(:pending), do: gettext("No pending documents to review.")
  defp empty_message(:approved), do: gettext("No approved documents.")
  defp empty_message(:rejected), do: gettext("No rejected documents.")
  defp empty_message(_), do: gettext("No verification documents found.")

  defp format_date(nil), do: ""
  defp format_date(%mod{} = date) when mod in [Date, DateTime], do: Calendar.strftime(date, "%b %d, %Y")

  # Admin-facing insurance-currency badge (AC item 3: "policy is current"). Maps the expiry status to a
  # design-token kh_pill tone — green when valid, amber (:warning) when expiring soon, red when lapsed.
  defp expiry_badge_label(:expired), do: gettext("Expired")
  defp expiry_badge_label(:expiring_soon), do: gettext("Expiring soon")
  defp expiry_badge_label(_), do: gettext("Valid")

  defp expiry_tone(:expired), do: :error
  defp expiry_tone(:expiring_soon), do: :warning
  defp expiry_tone(_), do: :success
end
