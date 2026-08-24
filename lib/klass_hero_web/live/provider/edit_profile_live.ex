defmodule KlassHeroWeb.Provider.EditProfileLive do
  @moduledoc """
  Provider profile editing: business description, logo, and verification-document
  uploads.

  Split out of the former `DashboardLive` god-module (#904). Unlike the other
  dashboard tabs it renders its own bare shell (no `pv_dashboard_chrome`), matching
  the pre-split behaviour, and is reached via `<.link navigate>` rather than a tab
  patch.
  """
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.ProviderComponents

  alias KlassHero.Provider
  alias KlassHeroWeb.Helpers.ProviderBranding
  alias KlassHeroWeb.Presenters.ProviderPresenter
  alias KlassHeroWeb.Provider.Dashboard.Chrome
  alias KlassHeroWeb.Provider.Dashboard.Uploads
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    provider = socket.assigns.current_scope.provider
    changeset = Provider.change_provider_profile(provider)
    docs = fetch_verification_docs(provider.id)
    trust_state = trust_state(provider.id)

    socket =
      socket
      |> Chrome.assign()
      |> assign(page_title: gettext("Edit Profile"))
      |> assign(active_nav: :home)
      |> assign(form: to_form(changeset, as: :provider_profile_schema))
      |> assign(revealed_socials: ProviderBranding.filled_networks(provider))
      |> assign(trust_state: trust_state)
      |> assign(preview: preview_view(changeset, trust_state))
      |> assign(preview_open?: false)
      |> assign(doc_type: "business_registration")
      |> assign(document_types: Provider.valid_document_types())
      |> stream(:verification_docs, docs, dom_id: &"vdoc-#{&1.id}")
      |> allow_upload(:logo,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 2_000_000
      )
      |> allow_upload(:cover,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 5_000_000
      )
      |> allow_upload(:verification_doc,
        accept: ~w(.pdf .jpg .jpeg .png),
        max_entries: 1,
        max_file_size: 10_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_profile", %{"provider_profile_schema" => params}, socket) do
    provider = socket.assigns.current_scope.provider
    changeset = Provider.change_provider_profile(provider, params)

    {:noreply,
     socket
     |> assign(form: to_form(Map.put(changeset, :action, :validate), as: :provider_profile_schema))
     |> assign(preview: preview_view(changeset, socket.assigns.trust_state))}
  end

  @impl true
  def handle_event("toggle_preview", _params, socket) do
    {:noreply, update(socket, :preview_open?, &(!&1))}
  end

  @impl true
  def handle_event("add_social_link", %{"network" => network}, socket) do
    {:noreply, update(socket, :revealed_socials, &ProviderBranding.reveal(&1, network))}
  end

  @impl true
  def handle_event("save_profile", %{"provider_profile_schema" => params}, socket) do
    provider = socket.assigns.current_scope.provider
    Logger.info("save_profile: starting", provider_id: provider.id)

    logo_result = Uploads.consume_single_upload(socket, :logo, "logos", provider.id)
    Logger.info("save_profile: logo upload result", provider_id: provider.id, result: logo_result)

    cover_result = Uploads.consume_single_upload(socket, :cover, "covers", provider.id)

    case {logo_result, cover_result} do
      {:upload_error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Logo upload failed. Please try again."))}

      {_, :upload_error} ->
        {:noreply, put_flash(socket, :error, gettext("Cover image upload failed. Please try again."))}

      {logo_result, cover_result} ->
        attrs =
          params
          |> ProviderBranding.attrs_from_params()
          |> Map.put(:description, params["description"])
          |> put_uploaded(:logo_url, logo_result)
          |> put_uploaded(:cover_image_url, cover_result)

        case Provider.update_provider_profile(provider.id, attrs) do
          {:ok, _updated} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Profile updated successfully."))
             |> push_navigate(to: ~p"/provider/dashboard")}

          {:error, {:validation_error, _errors}} ->
            {:noreply, put_flash(socket, :error, gettext("Please fix the errors below."))}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Provider profile not found."))
             |> push_navigate(to: ~p"/")}

          {:error, changeset} ->
            {:noreply, assign(socket, form: to_form(changeset, as: :provider_profile_schema))}
        end
    end
  end

  @impl true
  def handle_event("upload_verification_doc", _params, socket) do
    provider = socket.assigns.current_scope.provider
    doc_type = socket.assigns.doc_type

    case Uploads.safe_consume_uploaded_entries(socket, :verification_doc, fn %{path: path}, entry ->
           try do
             # sobelow_skip ["Traversal.FileModule"]
             file_binary = File.read!(path)

             case Provider.submit_verification_document(%{
                    provider_profile_id: provider.id,
                    document_type: doc_type,
                    file_binary: file_binary,
                    original_filename: entry.client_name,
                    content_type: entry.client_type
                  }) do
               {:ok, doc} -> {:ok, doc}
               {:error, reason} -> {:postpone, reason}
             end
           catch
             kind, reason ->
               Logger.error("Verification doc upload failed",
                 provider_id: provider.id,
                 doc_type: doc_type,
                 kind: kind,
                 error: inspect(reason)
               )

               {:error, :upload_exception}
           end
         end) do
      {:error, :upload_channel_died} ->
        {:noreply, put_flash(socket, :error, gettext("Upload connection lost. Please try again."))}

      # consume_uploaded_entries unwraps {:ok, value} → value
      {:ok, [%{} = doc]} ->
        {:noreply,
         socket
         |> stream_insert(:verification_docs, doc, dom_id: &"vdoc-#{&1.id}")
         |> put_flash(:info, gettext("Document uploaded successfully."))}

      {:ok, other} ->
        Logger.error("Verification document upload failed",
          provider_id: provider.id,
          doc_type: doc_type,
          errors: inspect(other)
        )

        {:noreply, put_flash(socket, :error, gettext("Failed to upload document."))}
    end
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_doc_type", %{"doc_type" => doc_type}, socket) do
    {:noreply, assign(socket, doc_type: doc_type)}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref, "upload" => upload_name}, socket) do
    {:noreply, cancel_upload(socket, String.to_existing_atom(upload_name), ref)}
  end

  # The preview renders the same component the public page does, fed by the same
  # presenter — `to_public_view/2` takes a struct, so applying the in-flight
  # changeset is enough and costs no query. A preview that re-implements the hero
  # is a preview that lies.
  defp preview_view(changeset, trust_state) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> ProviderPresenter.to_public_view(trust_state)
  end

  # get_trust_states/1 is batch-only; a missing entry means unverified. The badge
  # is not editable here, so this is read once at mount.
  defp trust_state(provider_id) do
    [provider_id]
    |> Provider.get_trust_states()
    |> Map.get(provider_id, :unverified)
  end

  defp fetch_verification_docs(provider_id) do
    {:ok, docs} = Provider.get_provider_verification_documents(provider_id)
    docs
  end

  defp put_uploaded(attrs, _key, :no_upload), do: attrs
  defp put_uploaded(attrs, key, {:ok, url}), do: Map.put(attrs, key, url)

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["min-h-screen", Theme.bg(:muted)]}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <div class="space-y-6">
          <div class="flex items-center gap-4 mb-6">
            <.link
              navigate={~p"/provider/dashboard"}
              class="flex items-center gap-1 text-[var(--fg-muted)] hover:text-hero-black-100 transition-colors"
            >
              <.icon name="hero-arrow-left-mini" class="w-5 h-5" />
              {gettext("Back to Dashboard")}
            </.link>
          </div>

          <h1 class="text-2xl font-bold text-hero-black-100">{gettext("Edit Profile")}</h1>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 items-start">
            <div class={["bg-white p-6 shadow-sm border border-hero-grey-200", Theme.rounded(:xl)]}>
              <h2 class="text-lg font-semibold text-hero-black-100 mb-4">
                {gettext("Provider Information")}
              </h2>

              <.form
                for={@form}
                id="profile-form"
                phx-change="validate_profile"
                phx-submit="save_profile"
                class="space-y-6"
              >
                <.input
                  field={@form[:description]}
                  type="textarea"
                  label={gettext("Provider Description")}
                  placeholder={gettext("Tell parents about your organization...")}
                  rows="4"
                />

                <div>
                  <label class="block text-sm font-semibold text-hero-black-100 mb-2">
                    {gettext("Provider Logo")}
                  </label>

                  <.pv_upload_dropzone
                    id="logo-upload"
                    upload={@uploads.logo}
                    name="logo"
                    trigger={gettext("Choose Logo")}
                    hint={gettext("JPG, PNG or WebP. Max 2MB.")}
                    preview_class="w-16 h-16 mx-auto rounded-full object-cover"
                  >
                    <:placeholder>
                      <div
                        :if={@business.initials}
                        class={[
                          "w-16 h-16 mx-auto flex items-center justify-center text-white text-xl font-bold",
                          Theme.rounded(:full),
                          Theme.gradient(:primary)
                        ]}
                      >
                        {@business.initials}
                      </div>
                    </:placeholder>
                  </.pv_upload_dropzone>
                </div>

                <.pv_branding_section
                  form={@form}
                  revealed={@revealed_socials}
                  uploads={@uploads}
                />

                <div class="flex justify-end">
                  <.kh_button
                    variant={:primary}
                    type="submit"
                    id="save-profile-btn"
                    icon="hero-check-mini"
                  >
                    {gettext("Save Changes")}
                  </.kh_button>
                </div>
              </.form>
            </div>

            <div class="lg:sticky lg:top-6">
              <%!-- A server assign, not a JS toggle: this form fires phx-change on
                    every keystroke and the resulting patch wipes an inline
                    display:none, so a JS-collapsed panel would reopen as you type. --%>
              <.kh_button
                variant={:ghost}
                type="button"
                id="toggle-preview"
                icon="hero-eye-mini"
                class="lg:hidden w-full"
                phx-click="toggle_preview"
                aria-expanded={to_string(@preview_open?)}
                aria-controls="profile-preview"
              >
                {if @preview_open?, do: gettext("Hide preview"), else: gettext("Show preview")}
              </.kh_button>

              <div
                id="profile-preview"
                class={[
                  "mt-4 lg:mt-0 overflow-hidden bg-white shadow-sm border border-hero-grey-200",
                  Theme.rounded(:xl),
                  !@preview_open? && "hidden lg:block"
                ]}
              >
                <div class="px-6 pt-6">
                  <h2 class="text-lg font-semibold text-hero-black-100">
                    {gettext("Public profile preview")}
                  </h2>
                  <p class="text-sm text-[var(--fg-muted)] mt-1">
                    {gettext("A newly chosen cover or logo appears here after you save.")}
                  </p>
                </div>

                <.provider_hero provider={@preview} variant={:full} />
              </div>
            </div>
          </div>

          <.verification_documents_panel
            verification_docs={@streams.verification_docs}
            uploads={@uploads}
            doc_type={@doc_type}
            document_types={@document_types}
          />
        </div>
      </div>
    </div>
    """
  end
end
