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
  alias KlassHeroWeb.Provider.Dashboard.Chrome
  alias KlassHeroWeb.Provider.Dashboard.Uploads
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    provider = socket.assigns.current_scope.provider
    changeset = Provider.change_provider_profile(provider)
    docs = fetch_verification_docs(provider.id)

    socket =
      socket
      |> Chrome.assign()
      |> assign(page_title: gettext("Edit Profile"))
      |> assign(active_nav: :home)
      |> assign(form: to_form(changeset, as: :provider_profile_schema))
      |> assign(doc_type: "business_registration")
      |> assign(document_types: Provider.valid_document_types())
      |> stream(:verification_docs, docs, dom_id: &"vdoc-#{&1.id}")
      |> allow_upload(:logo,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 2_000_000
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
     assign(socket,
       form: to_form(Map.put(changeset, :action, :validate), as: :provider_profile_schema)
     )}
  end

  @impl true
  def handle_event("save_profile", %{"provider_profile_schema" => params}, socket) do
    provider = socket.assigns.current_scope.provider
    Logger.info("save_profile: starting", provider_id: provider.id)

    logo_result = Uploads.consume_single_upload(socket, :logo, "logos", provider.id)
    Logger.info("save_profile: logo upload result", provider_id: provider.id, result: logo_result)

    case logo_result do
      :upload_error ->
        {:noreply, put_flash(socket, :error, gettext("Logo upload failed. Please try again."))}

      logo_result ->
        attrs = %{description: params["description"]}

        attrs =
          case logo_result do
            {:ok, url} -> Map.put(attrs, :logo_url, url)
            :no_upload -> attrs
          end

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

  defp fetch_verification_docs(provider_id) do
    {:ok, docs} = Provider.get_provider_verification_documents(provider_id)
    docs
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["min-h-screen", Theme.bg(:muted)]}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <div class="space-y-6">
          <div class="flex items-center gap-4 mb-6">
            <.link
              navigate={~p"/provider/dashboard"}
              class="flex items-center gap-1 text-hero-grey-500 hover:text-hero-black-100 transition-colors"
            >
              <.icon name="hero-arrow-left-mini" class="w-5 h-5" />
              {gettext("Back to Dashboard")}
            </.link>
          </div>

          <h1 class="text-2xl font-bold text-hero-black-100">{gettext("Edit Profile")}</h1>

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

                <div
                  id="logo-upload"
                  class={[
                    "border-2 border-dashed border-hero-grey-300 p-6 text-center",
                    Theme.rounded(:lg)
                  ]}
                  phx-drop-target={@uploads.logo.ref}
                >
                  <div :if={@business.initials} class="mb-4">
                    <div class={[
                      "w-16 h-16 mx-auto flex items-center justify-center text-white text-xl font-bold",
                      Theme.rounded(:full),
                      Theme.gradient(:primary)
                    ]}>
                      {@business.initials}
                    </div>
                  </div>

                  <%!-- Upload entries preview --%>
                  <div :for={entry <- @uploads.logo.entries} class="mb-4">
                    <.live_img_preview
                      entry={entry}
                      class="w-16 h-16 mx-auto rounded-full object-cover"
                    />
                    <p class="text-sm text-hero-grey-500 mt-1">{entry.client_name}</p>
                    <button
                      type="button"
                      phx-click="cancel_upload"
                      phx-value-ref={entry.ref}
                      phx-value-upload="logo"
                      class="text-xs text-red-500 hover:text-red-700 mt-1"
                    >
                      {gettext("Remove")}
                    </button>
                    <div
                      :for={err <- upload_errors(@uploads.logo, entry)}
                      class="text-xs text-red-500 mt-1"
                    >
                      {upload_error_to_string(err)}
                    </div>
                  </div>

                  <.live_file_input upload={@uploads.logo} class="hidden" />
                  <label
                    for={@uploads.logo.ref}
                    class={[
                      "inline-flex items-center gap-2 px-4 py-2 border border-hero-grey-300",
                      "bg-white hover:bg-hero-grey-50 text-hero-black-100 text-sm font-medium cursor-pointer",
                      Theme.rounded(:lg),
                      Theme.transition(:normal)
                    ]}
                  >
                    <.icon name="hero-photo-mini" class="w-4 h-4" />
                    {gettext("Choose Logo")}
                  </label>
                  <p class="text-xs text-hero-grey-400 mt-2">
                    {gettext("JPG, PNG or WebP. Max 2MB.")}
                  </p>
                </div>
              </div>

              <div class="flex justify-end">
                <button
                  type="submit"
                  id="save-profile-btn"
                  class={[
                    "flex items-center gap-2 px-6 py-2.5 bg-hero-yellow-500 hover:bg-hero-yellow-600",
                    "text-hero-black-100 font-semibold",
                    Theme.rounded(:lg),
                    Theme.transition(:normal)
                  ]}
                >
                  <.icon name="hero-check-mini" class="w-5 h-5" />
                  {gettext("Save Changes")}
                </button>
              </div>
            </.form>
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
