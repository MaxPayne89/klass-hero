defmodule KlassHeroWeb.Provider.ProfileCompletionLive do
  @moduledoc """
  LiveView for completing a draft provider profile.

  When a staff member deliberately upgrades to provider (#968, ADR-0005),
  a minimal profile is created in draft status. This page guides
  the new provider through filling in their business details.

  Pre-populates fields from the linked staff member record.
  """
  use KlassHeroWeb, :live_view

  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.Models.ProviderProfile
  alias KlassHero.Shared.Categories
  alias KlassHero.Shared.Storage
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
          |> assign(form: to_form(changeset))
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

    {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
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
          |> maybe_put_logo(logo_result)

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
             |> assign(form: to_form(Map.put(changeset, :action, :validate)))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Something went wrong. Please try again."))}
        end
    end
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :logo, ref)}
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

  # Matches the dashboard's consume_single_upload pattern: reads file binary,
  # sanitizes filename, calls Storage.upload/4 with correct arity.
  defp upload_logo(socket, provider_id) do
    case safe_consume_uploaded_entries(socket, fn %{path: path}, entry ->
           try do
             # sobelow_skip ["Traversal.FileModule"]
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
            class="flex items-center gap-1 text-gray-500 hover:text-gray-700 transition-colors"
          >
            <.icon name="hero-arrow-left-mini" class="w-5 h-5" />
            {gettext("Back to Dashboard")}
          </.link>
        </div>

        <h1 class={["text-2xl font-bold mb-2", Theme.typography(:page_title)]}>
          {gettext("Complete Your Provider Profile")}
        </h1>
        <p class="text-gray-500 mb-8">
          {gettext(
            "Fill in your business details. Your profile will be reviewed by Klass Hero before going live."
          )}
        </p>

        <div class={["bg-white p-6 shadow-sm border border-gray-200", Theme.rounded(:xl)]}>
          <.form
            for={@form}
            id="profile-completion-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-6"
          >
            <.input
              field={@form[:business_name]}
              type="text"
              label={gettext("Business Name")}
              placeholder={gettext("Your business or organization name")}
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
              placeholder={gettext("Your business address")}
            />

            <div>
              <label class="block text-sm font-semibold text-gray-700 mb-2">
                {gettext("Categories")}
              </label>
              <div class="flex flex-wrap gap-2">
                <label
                  :for={category <- @categories}
                  class={[
                    "inline-flex items-center gap-1.5 px-3 py-1.5 text-sm border cursor-pointer",
                    Theme.rounded(:lg),
                    "hover:bg-gray-50 transition-colors"
                  ]}
                >
                  <input
                    type="checkbox"
                    name="provider_profile_schema[categories][]"
                    value={category}
                    checked={category in (@form[:categories].value || [])}
                    class="rounded border-gray-300 text-brand focus:ring-brand"
                  />
                  <span class="capitalize">{category}</span>
                </label>
              </div>
              <input type="hidden" name="provider_profile_schema[categories][]" value="" />
            </div>

            <%!-- Logo Upload --%>
            <div>
              <label class="block text-sm font-semibold text-gray-700 mb-2">
                {gettext("Business Logo")}
              </label>
              <div
                id="logo-upload"
                class={[
                  "border-2 border-dashed border-gray-300 p-6 text-center",
                  Theme.rounded(:lg)
                ]}
                phx-drop-target={@uploads.logo.ref}
              >
                <.live_file_input upload={@uploads.logo} class="hidden" />
                <label for={@uploads.logo.ref} class="cursor-pointer">
                  <.icon name="hero-cloud-arrow-up" class="w-8 h-8 mx-auto text-gray-400 mb-2" />
                  <p class="text-sm text-gray-500">
                    {gettext("Drag and drop or click to upload")}
                  </p>
                  <p class="text-xs text-gray-400 mt-1">
                    {gettext("JPG, PNG or WebP. Max 2MB.")}
                  </p>
                </label>
              </div>

              <div :for={entry <- @uploads.logo.entries} class="mt-3 flex items-center gap-3">
                <.live_img_preview entry={entry} class="w-12 h-12 rounded object-cover" />
                <span class="text-sm text-gray-600">{entry.client_name}</span>
                <button
                  type="button"
                  phx-click="cancel_upload"
                  phx-value-ref={entry.ref}
                  class="text-red-500 hover:text-red-700 text-sm"
                >
                  {gettext("Remove")}
                </button>
              </div>
            </div>

            <div class="flex justify-end pt-4 border-t border-gray-200">
              <.button type="submit" phx-disable-with={gettext("Saving...")}>
                {gettext("Complete Profile")}
              </.button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end
end
