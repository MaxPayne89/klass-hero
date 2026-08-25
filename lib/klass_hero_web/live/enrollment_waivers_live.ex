defmodule KlassHeroWeb.EnrollmentWaiversLive do
  @moduledoc """
  Signing the waivers outstanding on an existing enrollment.

  Reached from the parent dashboard when an enrollment was created without a signer present
  — a provider's bulk invite creates the enrollment from a background job, so the waivers
  stay outstanding until the parent gets here.

  ## Only the enrolling parent

  Authorization runs on **mount and on submit**, not mount alone: a mount-only check leaves
  the submit event reachable directly over the socket by anyone who can guess an enrollment
  id. `Enrollment.sign_waivers/4` re-checks server-side regardless, so this is
  defence in depth rather than the only guard.
  """
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.BookingComponents, only: [waiver_requirement: 1]

  alias KlassHero.Enrollment
  alias KlassHero.Family
  alias KlassHero.ProgramCatalog
  alias KlassHeroWeb.AuditInfo
  alias KlassHeroWeb.Theme

  @impl true
  def mount(%{"id" => enrollment_id}, _session, socket) do
    case authorize(socket, enrollment_id) do
      {:ok, enrollment, parent} ->
        {:ok,
         socket
         |> assign(
           page_title: gettext("Waivers"),
           active_nav: :bookings,
           enrollment: enrollment,
           parent_id: parent.id,
           program_title: program_title(enrollment.program_id),
           waivers: Enrollment.list_enrollment_waivers(enrollment_id),
           audit: AuditInfo.from_socket(socket)
         )}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Enrollment not found."))
         |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event("sign_waivers", params, socket) do
    %{enrollment: enrollment, parent_id: parent_id} = socket.assigns
    version_ids = List.wrap(params["waiver_version_ids"])

    case Enrollment.sign_waivers(enrollment.id, parent_id, version_ids, socket.assigns.audit) do
      {:ok, []} ->
        {:noreply, put_flash(socket, :error, gettext("Please tick a waiver to sign it."))}

      {:ok, _acceptances} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Thank you — your waivers are on record."))
         |> push_navigate(to: ~p"/dashboard")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Enrollment not found."))
         |> redirect(to: ~p"/dashboard")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(waivers: Enrollment.list_enrollment_waivers(enrollment.id))
         |> put_flash(:error, gettext("Something went wrong. Please try again or contact support."))}
    end
  end

  defp authorize(socket, enrollment_id) do
    identity_id = socket.assigns.current_scope.user.id

    with {:ok, parent} <- Family.get_parent_by_identity(identity_id),
         {:ok, enrollment} <- Enrollment.get_enrollment(enrollment_id),
         # A foreign enrollment is reported exactly like a missing one, so probing ids
         # reveals nothing about which exist.
         true <- enrollment.parent_id == parent.id do
      {:ok, enrollment, parent}
    else
      _otherwise -> {:error, :not_found}
    end
  end

  defp program_title(program_id) do
    case ProgramCatalog.get_program_by_id(program_id) do
      {:ok, program} -> program.title
      {:error, _reason} -> gettext("this program")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-6">
      <h1 class={[Theme.typography(:page_title), Theme.text_color(:heading), "mb-2"]}>
        {gettext("Waivers")}
      </h1>
      <p class={["mb-6", Theme.text_color(:secondary)]}>
        {gettext("Please read and sign these before %{program} begins.", program: @program_title)}
      </p>

      <p :if={@waivers == []} id="waivers-none" class={Theme.text_color(:secondary)}>
        {gettext("There is nothing to sign for this enrollment.")}
      </p>

      <form
        :if={@waivers != []}
        id="sign-waivers-form"
        phx-submit="sign_waivers"
        phx-auto-recover="ignore"
        class="space-y-6"
      >
        <div
          :for={entry <- @waivers}
          id={"waiver-#{entry.waiver.id}"}
          class={[Theme.bg(:surface), Theme.rounded(:xl), "p-6 shadow-lg"]}
        >
          <h2 class={[
            Theme.typography(:card_title),
            Theme.text_color(:heading),
            "mb-2 flex flex-wrap items-center gap-2"
          ]}>
            {entry.waiver.title}
            <.waiver_requirement required={entry.waiver.required} />
          </h2>

          <div
            class={[
              "max-h-64 overflow-y-auto border p-3 text-sm whitespace-pre-line mb-3",
              Theme.rounded(:lg),
              Theme.border_color(:medium),
              Theme.text_color(:body)
            ]}
            tabindex="0"
          >
            {entry.version.body}
          </div>

          <p :if={entry.signed?} id={"waiver-signed-#{entry.waiver.id}"}>
            <.status_pill color="success">{gettext("Signed")}</.status_pill>
          </p>

          <label :if={!entry.signed?} class="flex items-start gap-2 text-sm cursor-pointer">
            <input
              type="checkbox"
              id={"sign-waiver-#{entry.waiver.id}"}
              name="waiver_version_ids[]"
              value={entry.version.id}
              class="mt-0.5"
            />
            <span class={Theme.text_color(:body)}>
              {gettext("I have read and agree to %{title}", title: entry.waiver.title)}
            </span>
          </label>
        </div>

        <.kh_button type="submit" id="submit-waivers" class="w-full">
          {gettext("Sign waivers")}
        </.kh_button>
      </form>
    </div>
    """
  end
end
