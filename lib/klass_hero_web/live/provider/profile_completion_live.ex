defmodule KlassHeroWeb.Provider.ProfileCompletionLive do
  @moduledoc """
  LiveView for completing a draft provider profile.

  When a staff member deliberately upgrades to provider (#968, ADR-0005),
  a minimal profile is created in draft status. This page guides
  the new provider through filling in their business details.

  Pre-populates fields from the linked staff member record.
  """
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.ProviderComponents

  alias KlassHero.Provider
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Shared.Categories
  alias KlassHero.Shared.FeatureFlags
  alias KlassHero.Shared.Storage
  alias KlassHeroWeb.Helpers.ProviderBranding
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    provider = socket.assigns.current_scope.provider

    case provider do
      %ProviderProfile{profile_status: :active} ->
        {:ok,
         socket
         |> put_flash(:info, gettext("Your profile is already complete."))
         |> redirect(to: ~p"/provider/dashboard")}

      %ProviderProfile{profile_status: :draft} ->
        staff_member = socket.assigns.current_scope.staff_member
        pre_filled_attrs = build_pre_fill(staff_member, provider)

        changeset = Provider.change_provider_profile_completion(provider, pre_filled_attrs)

        socket =
          socket
          |> assign(page_title: gettext("Complete Your Profile"))
          |> assign(active_nav: :onboarding)
          |> assign(provider: provider)
          |> assign(business_vetting?: business_vetting_enabled?())
          |> assign(form: to_form(changeset, as: :provider_profile_schema))
          |> assign(revealed_socials: ProviderBranding.filled_networks(provider))
          |> assign(categories: Categories.categories())
          |> allow_upload(:logo,
            accept: ~w(.jpg .jpeg .png .webp),
            max_entries: 1,
            max_file_size: 2_000_000
          )

        {:ok, socket}

      _ ->
        {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_event("validate", %{"provider_profile_schema" => params}, socket) do
    provider = socket.assigns.provider
    changeset = Provider.change_provider_profile_completion(provider, params)

    {:noreply,
     assign(socket,
       form: to_form(Map.put(changeset, :action, :validate), as: :provider_profile_schema)
     )}
  end

  @impl true
  def handle_event("save", %{"provider_profile_schema" => params}, socket) do
    provider = socket.assigns.provider

    logo_result = upload_logo(socket, provider.id)

    case logo_result do
      :upload_error ->
        {:noreply, put_flash(socket, :error, gettext("Logo upload failed. Please try again."))}

      logo_result ->
        attrs =
          %{
            business_name: params["business_name"],
            description: params["description"],
            phone: blank_to_nil(params["phone"]),
            website: blank_to_nil(params["website"]),
            address: blank_to_nil(params["address"]),
            categories: parse_categories(params["categories"])
          }
          |> Map.merge(ProviderBranding.attrs_from_params(params))
          |> maybe_put_logo(logo_result)
          |> maybe_put_entity_type(socket.assigns.business_vetting?, params)

        case Provider.complete_provider_profile(provider.id, attrs) do
          {:ok, _completed} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Profile completed! Klass Hero will review your profile shortly."))
             |> push_navigate(to: ~p"/provider/dashboard")}

          {:error, {:validation_error, _errors}} ->
            changeset = Provider.change_provider_profile_completion(provider, params)

            {:noreply,
             socket
             |> put_flash(:error, gettext("Please fix the errors below."))
             |> assign(form: to_form(Map.put(changeset, :action, :validate), as: :provider_profile_schema))}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, form: to_form(changeset, as: :provider_profile_schema))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Something went wrong. Please try again."))}
        end
    end
  end

  @impl true
  def handle_event("add_social_link", %{"network" => network}, socket) do
    {:noreply, update(socket, :revealed_socials, &ProviderBranding.reveal(&1, network))}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref, "upload" => upload_name}, socket) do
    {:noreply, cancel_upload(socket, String.to_existing_atom(upload_name), ref)}
  end

  defp build_pre_fill(nil, _provider), do: %{}

  # Post-#968 the staff record belongs to an EMPLOYER's business, not the new
  # draft profile — bio/tags are person-level attributes pre-filled into a
  # fully editable form. With multiple employments the scope's currently
  # selected employment wins (#969 switcher: last_selected_at, then
  # employer-first, then newest — see active_memberships_query).
  defp build_pre_fill(staff_member, _provider) do
    %{}
    |> maybe_put_value(:description, staff_member.bio)
    |> maybe_put_value(:categories, staff_member.tags)
  end

  defp maybe_put_value(map, _key, nil), do: map
  defp maybe_put_value(map, _key, []), do: map
  defp maybe_put_value(map, key, value), do: Map.put(map, key, value)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp parse_categories(nil), do: []

  defp parse_categories(cats) when is_list(cats) do
    cats
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp parse_categories(_), do: []

  defp maybe_put_logo(attrs, :no_upload), do: attrs
  defp maybe_put_logo(attrs, {:ok, url}), do: Map.put(attrs, :logo_url, url)

  # Fail-safe flag read: any error (adapter down, agent absent) collapses to "off", so the
  # business track can never leak on by accident. First production consumer of FeatureFlags.
  defp business_vetting_enabled? do
    case FeatureFlags.enabled?(:business_vetting) do
      {:ok, enabled?} -> enabled?
      {:error, _} -> false
    end
  end

  # Default-deny gate for the business-vetting entity_type choice, the trust boundary between a
  # raw form param and a persisted vetting-track switch (complete_provider_profile/2 copies
  # :entity_type straight onto the struct). Writes the field only when the flag is on AND the
  # value is a known choice; the catch-all clause leaves attrs untouched for every other case
  # (flag off, key absent, unknown value), so a hand-crafted POST can never flip the track.
  defp maybe_put_entity_type(attrs, true, %{"entity_type" => type}) when type in ["individual", "business"] do
    Map.put(attrs, :entity_type, String.to_existing_atom(type))
  end

  defp maybe_put_entity_type(attrs, _business_vetting?, _params), do: attrs

  # sobelow_skip ["Traversal.FileModule"]
  # The path comes from consume_uploaded_entries — a LiveView-generated temp file, not
  # from the client. The uploader controls the filename, never this path.
  defp upload_logo(socket, provider_id) do
    case safe_consume_uploaded_entries(socket, fn %{path: path}, entry ->
           try do
             file_binary = File.read!(path)
             safe_name = String.replace(entry.client_name, ~r/[^a-zA-Z0-9._-]/, "_")
             storage_path = "logos/providers/#{provider_id}/#{safe_name}"

             Storage.upload(:public, storage_path, file_binary, content_type: entry.client_type)
           catch
             kind, reason ->
               Logger.error("Logo upload failed",
                 provider_id: provider_id,
                 kind: kind,
                 error: inspect(reason)
               )

               {:error, :upload_exception}
           end
         end) do
      {:error, :upload_channel_died} -> :upload_error
      {:ok, [url]} when is_binary(url) -> {:ok, url}
      {:ok, []} -> :no_upload
      {:ok, _other} -> :upload_error
    end
  end

  defp safe_consume_uploaded_entries(socket, callback) do
    {:ok, consume_uploaded_entries(socket, :logo, callback)}
  catch
    :exit, reason ->
      Logger.warning("Upload channel process died during consume", reason: inspect(reason))
      {:error, :upload_channel_died}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["min-h-screen", Theme.bg(:muted)]}>
      <div class="max-w-2xl mx-auto px-4 sm:px-6 py-8">
        <div class="mb-6">
          <.link
            navigate={~p"/provider/dashboard"}
            class="flex items-center gap-1 text-[var(--fg-muted)] hover:text-hero-black-100 transition-colors"
          >
            <.icon name="hero-arrow-left-mini" class="w-5 h-5" />
            {gettext("Back to Dashboard")}
          </.link>
        </div>

        <h1 class={["text-2xl font-bold mb-2", Theme.typography(:page_title)]}>
          {gettext("Complete Your Provider Profile")}
        </h1>
        <p class="text-[var(--fg-muted)] mb-8">
          {gettext(
            "Fill in your business details. Your profile will be reviewed by Klass Hero before going live."
          )}
        </p>

        <div class={["bg-white p-6 shadow-sm border border-hero-grey-200", Theme.rounded(:xl)]}>
          <.form
            for={@form}
            id="profile-completion-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-6"
          >
            <div :if={@business_vetting?}>
              <label class="block text-sm font-semibold text-hero-black-100 mb-2">
                {gettext("What are you registering as?")}
              </label>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <label
                  :for={
                    {value, title, hint} <- [
                      {"individual", gettext("An individual"),
                       gettext("You'll be vetted personally.")},
                      {"business", gettext("A business"),
                       gettext("Your business and its responsible person will be vetted.")}
                    ]
                  }
                  class={[
                    "flex items-start gap-3 p-3 border cursor-pointer hover:bg-hero-grey-50 transition-colors",
                    Theme.rounded(:lg)
                  ]}
                >
                  <input
                    type="radio"
                    name="provider_profile_schema[entity_type]"
                    value={value}
                    checked={to_string(@form[:entity_type].value) == value}
                    class="mt-1 border-hero-grey-300 text-[var(--brand-primary)] focus:ring-[var(--focus-ring)]"
                  />
                  <span class="flex flex-col">
                    <span class="text-sm font-medium text-hero-black">{title}</span>
                    <span class="text-xs text-[var(--fg-muted)]">{hint}</span>
                  </span>
                </label>
              </div>
            </div>

            <.input
              field={@form[:business_name]}
              type="text"
              label={gettext("Provider Name")}
              placeholder={gettext("Your provider or organization name")}
            />

            <.input
              field={@form[:description]}
              type="textarea"
              label={gettext("Description")}
              placeholder={
                gettext("Tell parents about your organization and what makes you unique...")
              }
              rows="4"
            />

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <.input
                field={@form[:phone]}
                type="text"
                label={gettext("Phone")}
                placeholder={gettext("+1234567890")}
              />

              <.input
                field={@form[:website]}
                type="text"
                label={gettext("Website")}
                placeholder="https://"
              />
            </div>

            <.input
              field={@form[:address]}
              type="text"
              label={gettext("Address")}
              placeholder={gettext("Your address")}
            />

            <div>
              <label class="block text-sm font-semibold text-hero-black-100 mb-2">
                {gettext("Categories")}
              </label>
              <div class="flex flex-wrap gap-2">
                <label
                  :for={category <- @categories}
                  class={[
                    "inline-flex items-center gap-1.5 px-3 py-1.5 text-sm border cursor-pointer",
                    Theme.rounded(:lg),
                    "hover:bg-hero-grey-50 transition-colors"
                  ]}
                >
                  <input
                    type="checkbox"
                    name="provider_profile_schema[categories][]"
                    value={category}
                    checked={category in (@form[:categories].value || [])}
                    class="rounded border-hero-grey-300 text-[var(--brand-primary)] focus:ring-[var(--focus-ring)]"
                  />
                  <span class="capitalize">{category}</span>
                </label>
              </div>
              <input type="hidden" name="provider_profile_schema[categories][]" value="" />
            </div>

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
              />
            </div>

            <.pv_branding_section form={@form} revealed={@revealed_socials} />

            <div class="flex justify-end pt-4 border-t border-hero-grey-200">
              <.kh_button variant={:primary} type="submit" phx-disable-with={gettext("Saving...")}>
                {gettext("Complete Profile")}
              </.kh_button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end
end
