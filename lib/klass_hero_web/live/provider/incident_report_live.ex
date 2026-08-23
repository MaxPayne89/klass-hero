defmodule KlassHeroWeb.Provider.IncidentReportLive do
  @moduledoc """
  Provider-facing page for submitting an incident report.

  The report is tied to a program selected by the provider (via `?program_id=`
  preselection or via the dropdown). Invalid program preselections redirect
  to the provider dashboard with an error flash.

  Session-scoped reports are supported by the underlying use case but not
  yet exposed in this UI — see issue #738.
  """

  use KlassHeroWeb, :live_view

  alias KlassHero.Provider
  alias KlassHero.Provider.IncidentReport
  alias KlassHero.Provider.ProviderProfile
  alias KlassHeroWeb.Helpers.DateTimeHelpers
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(params, _session, socket) do
    case socket.assigns.current_scope.provider do
      %ProviderProfile{} = provider ->
        mount_for_provider(socket, provider, params)

      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Provider profile not found."))
         |> push_navigate(to: ~p"/")}
    end
  end

  defp mount_for_provider(socket, provider, params) do
    case resolve_preselection(params, provider.id) do
      {:ok, preselected} ->
        programs = Provider.list_provider_programs(provider.id)

        socket =
          socket
          |> assign(
            page_title: gettext("Report an Incident"),
            active_nav: :programs,
            provider: provider,
            programs: programs,
            preselected: preselected,
            form: empty_form(preselected)
          )
          |> allow_upload(:photo,
            accept: ~w(.jpg .jpeg .png .webp),
            max_entries: 1,
            max_file_size: 10_000_000
          )

        {:ok, socket}

      {:error, :preselection_invalid} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Program or session not found."))
         |> push_navigate(to: ~p"/provider/dashboard")}
    end
  end

  defp resolve_preselection(%{"program_id" => program_id}, provider_id) when is_binary(program_id) do
    case Provider.get_provider_program(program_id, provider_id) do
      {:ok, program} -> {:ok, {:program, program}}
      {:error, :not_found} -> {:error, :preselection_invalid}
    end
  end

  defp resolve_preselection(_params, _provider_id), do: {:ok, :none}

  defp empty_form(preselected) do
    program_id =
      case preselected do
        {:program, program} -> program.program_id
        _ -> nil
      end

    params = %{
      "program_id" => program_id,
      "category" => nil,
      "severity" => nil,
      "description" => "",
      "occurred_at" => nil
    }

    to_form(params, as: "incident")
  end

  defp selected_program_id({:program, program}), do: program.program_id
  defp selected_program_id(_), do: nil

  @impl true
  def handle_event("validate", %{"incident" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: "incident"))}
  end

  def handle_event("save", %{"incident" => params}, socket) do
    photo_params = consume_photo(socket)

    submit_params =
      params
      |> build_submit_params(socket.assigns.provider.id, socket.assigns.current_scope.user)
      |> Map.merge(photo_params)

    case Provider.submit_incident_report(submit_params) do
      {:ok, _report} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Incident report submitted."))
         |> push_navigate(to: ~p"/provider/dashboard")}

      {:error, errors} when is_list(errors) ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Please fix the errors below."))
         |> assign(form: form_with_errors(params, errors))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Please fix the errors below."))
         |> assign(form: form_with_changeset_errors(params, changeset))}

      {:error, reason} ->
        Logger.warning("Incident report submission failed", reason: inspect(reason))
        {:noreply, put_flash(socket, :error, gettext("Something went wrong. Please try again."))}
    end
  end

  # Returns a partial param map with file data, or %{file_binary: nil} when no photo was uploaded.
  defp consume_photo(socket) do
    case safe_consume_photo(socket) do
      {:ok, [photo]} ->
        %{
          file_binary: photo.binary,
          original_filename: photo.original_filename,
          content_type: photo.content_type
        }

      _ ->
        %{file_binary: nil}
    end
  end

  defp safe_consume_photo(socket) do
    {:ok,
     consume_uploaded_entries(socket, :photo, fn %{path: path}, entry ->
       # sobelow_skip ["Traversal.FileModule"]
       {:ok,
        %{
          binary: File.read!(path),
          original_filename: entry.client_name,
          content_type: entry.client_type
        }}
     end)}
  catch
    :exit, reason ->
      Logger.warning("Photo upload channel died during consume", reason: inspect(reason))
      {:error, :upload_channel_died}
  end

  defp build_submit_params(params, provider_id, user) do
    %{
      provider_profile_id: provider_id,
      reporter_user_id: user.id,
      reporter_display_name: reporter_display_name(user),
      program_id: blank_to_nil(params["program_id"]),
      session_id: blank_to_nil(params["session_id"]),
      category: atomize(params["category"]),
      severity: atomize(params["severity"]),
      description: params["description"] || "",
      occurred_at: DateTimeHelpers.parse_datetime_local(params["occurred_at"])
    }
  end

  # User.name is optional; fall back to email so the reporter snapshot is always populated for audit.
  defp reporter_display_name(%{name: name, email: email}) when is_binary(name) do
    case String.trim(name) do
      "" -> email
      trimmed -> trimmed
    end
  end

  defp reporter_display_name(%{email: email}), do: email

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp atomize(nil), do: nil
  defp atomize(""), do: nil
  defp atomize(value) when is_atom(value), do: value

  # Guard against form-tampered values by restricting to the explicit allow-list of legitimate atoms.
  defp atomize(value) when is_binary(value) do
    atom = String.to_existing_atom(value)
    if atom in valid_form_atoms(), do: atom
  rescue
    ArgumentError -> nil
  end

  defp valid_form_atoms, do: IncidentReport.valid_categories() ++ IncidentReport.valid_severities()

  defp form_with_errors(params, errors) do
    form_errors = Enum.map(errors, fn {field, message} -> {field, {to_string(message), []}} end)
    to_form(params, as: "incident", errors: form_errors)
  end

  # Changeset errors arrive as `{field, {template, opts}}`; interpolate the opts
  # (e.g. %{count}) so inline messages read "at least 10 characters", not the raw template.
  defp form_with_changeset_errors(params, changeset) do
    form_errors =
      Enum.map(changeset.errors, fn {field, {template, opts}} ->
        {field, {interpolate_error(template, opts), []}}
      end)

    to_form(params, as: "incident", errors: form_errors)
  end

  defp interpolate_error(template, opts) do
    Enum.reduce(opts, template, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp category_options do
    for cat <- IncidentReport.valid_categories(), do: {format_category(cat), Atom.to_string(cat)}
  end

  defp format_category(:safety_concern), do: gettext("Safety Concern")
  defp format_category(:behavioral_issue), do: gettext("Behavioral Issue")
  defp format_category(:injury), do: gettext("Injury")
  defp format_category(:property_damage), do: gettext("Property Damage")
  defp format_category(:policy_violation), do: gettext("Policy Violation")
  defp format_category(:other), do: gettext("Other")

  defp severity_options do
    for sev <- IncidentReport.valid_severities(), do: {format_severity(sev), Atom.to_string(sev)}
  end

  defp format_severity(:low), do: gettext("Low")
  defp format_severity(:medium), do: gettext("Medium")
  defp format_severity(:high), do: gettext("High")
  defp format_severity(:critical), do: gettext("Critical")

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["min-h-screen", Theme.bg(:muted)]}>
      <div class="max-w-2xl mx-auto px-4 sm:px-6 py-8">
        <div class="mb-6">
          <.link
            navigate={~p"/provider/dashboard"}
            class="flex items-center gap-1 text-hero-grey-500 hover:text-hero-grey-700 transition-colors"
          >
            <.icon name="hero-arrow-left-mini" class="w-5 h-5" />
            {gettext("Back to Dashboard")}
          </.link>
        </div>

        <h1 class={Theme.typography(:page_title)}>
          {gettext("Report an Incident")}
        </h1>
        <p class={[
          Theme.typography(:body_small),
          "mt-2 text-hero-grey-600"
        ]}>
          {gettext(
            "Submit a report about an incident during a program or session. All fields are confidential."
          )}
        </p>

        <.form
          for={@form}
          id="incident-report-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-6 space-y-5"
          data-selected-program={selected_program_id(@preselected)}
        >
          <.input
            field={@form[:occurred_at]}
            type="datetime-local"
            label={gettext("Date & time")}
            required
          />

          <.input
            field={@form[:program_id]}
            type="select"
            label={gettext("Program")}
            options={Enum.map(@programs, &{&1.name, &1.program_id})}
            prompt={gettext("Select a program")}
            required
          />

          <.input
            field={@form[:category]}
            type="select"
            label={gettext("Category")}
            options={category_options()}
            prompt={gettext("Select a category")}
            required
          />

          <.input
            field={@form[:severity]}
            type="select"
            label={gettext("Severity")}
            options={severity_options()}
            required
          />

          <.input
            field={@form[:description]}
            type="textarea"
            label={gettext("Description")}
            rows="6"
            required
          />

          <div>
            <label class="block text-sm font-medium text-hero-black-100 mb-2">
              {gettext("Photo (optional)")}
            </label>

            <label
              for={@uploads.photo.ref}
              phx-drop-target={@uploads.photo.ref}
              class={[
                "flex flex-col items-center justify-center border-2 border-dashed border-hero-grey-300 rounded-lg p-6 cursor-pointer hover:border-hero-blue-500",
                "has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-[var(--brand-primary)] has-[:focus-visible]:ring-offset-2"
              ]}
            >
              <.live_file_input upload={@uploads.photo} class="sr-only" />
              <span class={Theme.typography(:body_small)}>
                {gettext("Drop a photo here or click to browse")}
              </span>
            </label>

            <ul :if={@uploads.photo.entries != []} class="mt-2 space-y-1 text-sm">
              <li :for={entry <- @uploads.photo.entries}>
                {entry.client_name} ({trunc(entry.client_size / 1024)} KB)
              </li>
            </ul>
          </div>

          <div class="flex justify-end gap-3 pt-4">
            <.link
              navigate={~p"/provider/dashboard"}
              class="text-hero-grey-600 hover:text-hero-black-100"
            >
              {gettext("Cancel")}
            </.link>
            <button
              type="submit"
              class={[
                Theme.gradient(:primary),
                "rounded-full px-6 py-2 text-white font-medium"
              ]}
            >
              {gettext("Submit report")}
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
