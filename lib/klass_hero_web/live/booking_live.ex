defmodule KlassHeroWeb.BookingLive do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.BookingComponents

  alias KlassHero.Enrollment
  alias KlassHero.Family
  alias KlassHero.ProgramCatalog
  alias KlassHeroWeb.AuditInfo
  alias KlassHeroWeb.Presenters.ChildPresenter
  alias KlassHeroWeb.Presenters.ProgramPresenter
  alias KlassHeroWeb.Theme

  @impl true
  def mount(%{"id" => program_id}, _session, socket) do
    with {:ok, program} <- fetch_program(program_id),
         :ok <- validate_registration_open(program),
         :ok <- validate_program_capacity(program) do
      identity_id = socket.assigns.current_scope.user.id

      # Resolve parent once to load their children (1 DB round-trip).
      {_parent, children} =
        case Family.get_parent_by_identity(identity_id) do
          {:ok, parent} -> {parent, Family.get_children(parent.id)}
          {:error, :not_found} -> {nil, []}
        end

      children_for_view = Enum.map(children, &ChildPresenter.to_simple_view/1)
      children_by_id = Map.new(children, &{&1.id, &1})

      # price is NOT NULL in DB and @enforce_keys in domain — nil here is a bug, not a normal condition.
      total_amount = program.price

      socket =
        socket
        |> assign(
          page_title: gettext("Enrollment - %{title}", title: program.title),
          active_nav: :bookings,
          program: program,
          schedule_brief: ProgramPresenter.format_schedule_brief(program),
          children: children_for_view,
          children_by_id: children_by_id,
          selected_child_id: nil,
          eligibility_status: nil,
          special_requirements: "",
          payment_method: "card",
          total_amount: total_amount,
          waivers: Enrollment.list_program_waivers(program.id),
          # Connect info exists only on the connected mount, so capture it here and read it
          # from assigns at submit — it is unreachable from a handle_event.
          audit: AuditInfo.from_socket(socket)
        )

      {:ok, socket}
    else
      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Program not found"))
         |> redirect(to: ~p"/programs")}

      {:error, :program_full} ->
        program_for_redirect = fetch_program_unsafe(program_id)

        {:ok,
         socket
         |> put_flash(
           :error,
           gettext("Sorry, this program is currently full. Check back later for availability.")
         )
         |> redirect(to: ~p"/programs/#{program_for_redirect.id}")}

      {:error, :registration_not_open} ->
        program_for_redirect = fetch_program_unsafe(program_id)

        {:ok,
         socket
         |> put_flash(:error, gettext("Registration is not currently open for this program."))
         |> redirect(to: ~p"/programs/#{program_for_redirect.id}")}
    end
  end

  @impl true
  def handle_event("back_to_program", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/programs/#{socket.assigns.program.id}")}
  end

  @impl true
  def handle_event("select_payment_method", %{"method" => method}, socket) do
    {:noreply, assign(socket, payment_method: method)}
  end

  @impl true
  def handle_event("booking_form_changed", params, socket) do
    child_id = params["child_id"]

    socket =
      if child_id not in [nil, ""] and child_id != socket.assigns.selected_child_id do
        select_child(socket, child_id)
      else
        assign(socket, :special_requirements, params["special_requirements"] || "")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("complete_enrollment", params, socket) do
    case socket.assigns.eligibility_status do
      {:ineligible, _reasons} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Selected child does not meet the program requirements.")
         )}

      _ ->
        with :ok <- validate_enrollment_data(socket, params),
             :ok <- validate_payment_method(socket),
             :ok <- validate_registration_open(socket.assigns.program),
             {:ok, _enrollment} <- create_enrollment(socket, params) do
          {:noreply,
           socket
           |> put_flash(
             :info,
             gettext("Enrollment successful! You'll receive a confirmation email shortly.")
           )
           |> push_navigate(to: ~p"/dashboard")}
        else
          {:error, :program_full} ->
            {:noreply,
             socket
             |> put_flash(
               :error,
               gettext("Sorry, this program is now full. Please choose another program.")
             )
             |> push_navigate(to: ~p"/programs")}

          {:error, :registration_not_open} ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Registration has closed for this program."))
             |> push_navigate(to: ~p"/programs/#{socket.assigns.program.id}")}

          {:error, :invalid_payment} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Payment information is invalid. Please check your details.")
             )}

          {:error, :child_not_selected} ->
            {:noreply, put_flash(socket, :error, gettext("Please select a child for enrollment."))}

          # Reachable two ways: the parent left a box unticked, or the provider published a
          # new version while this page was open. Re-read the waivers so the second case
          # shows the text now in force rather than the stale copy they were looking at.
          {:error, :waivers_unsigned} ->
            {:noreply,
             socket
             |> assign(waivers: Enrollment.list_program_waivers(socket.assigns.program.id))
             |> put_flash(:error, gettext("Please read and sign every required waiver before enrolling."))}

          {:error, :no_parent_profile} ->
            {:noreply,
             socket
             |> put_flash(
               :error,
               gettext("Please complete your profile before making a booking.")
             )
             |> push_navigate(to: ~p"/users/settings#profiles")}

          {:error, :ineligible, reasons} ->
            {:noreply,
             socket
             |> assign(eligibility_status: {:ineligible, reasons})
             |> put_flash(
               :error,
               gettext("Selected child does not meet the program requirements.")
             )}

          {:error, :duplicate_resource} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("This child is already enrolled in this program.")
             )}

          {:error, :processing_failed} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Enrollment failed. Please try again or contact support.")
             )}

          {:error, _reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Something went wrong. Please try again or contact support.")
             )}
        end
    end
  end

  defp fetch_program(id) do
    ProgramCatalog.get_program_by_id(id)
  end

  defp fetch_program_unsafe(program_id) do
    case ProgramCatalog.get_program_by_id(program_id) do
      {:ok, program} -> program
      {:error, _} -> %{id: program_id}
    end
  end

  defp validate_registration_open(program) do
    if ProgramCatalog.registration_open?(program) do
      :ok
    else
      {:error, :registration_not_open}
    end
  end

  defp validate_program_capacity(program) do
    case Enrollment.remaining_capacity(program.id) do
      {:ok, :unlimited} ->
        :ok

      {:ok, remaining} when remaining > 0 ->
        :ok

      {:ok, _} ->
        {:error, :program_full}
    end
  end

  defp validate_enrollment_data(_socket, %{"child_id" => child_id})
       when is_binary(child_id) and byte_size(child_id) > 0, do: :ok

  defp validate_enrollment_data(_socket, _params), do: {:error, :child_not_selected}

  defp validate_payment_method(socket) do
    case socket.assigns.payment_method do
      method when method in ["card", "transfer"] -> :ok
      _ -> {:error, :invalid_payment}
    end
  end

  defp create_enrollment(socket, params) do
    identity_id = socket.assigns.current_scope.user.id

    enrollment_params = %{
      identity_id: identity_id,
      program_id: socket.assigns.program.id,
      child_id: params["child_id"],
      payment_method: socket.assigns.payment_method,
      subtotal: socket.assigns.total_amount,
      vat_amount: Decimal.new("0.00"),
      card_fee_amount: Decimal.new("0.00"),
      total_amount: socket.assigns.total_amount,
      special_requirements: params["special_requirements"],
      # A signer is present here, so the intent is always `:accepted` — never `:deferred`.
      # The context re-checks the set against the program's current required waivers, so a
      # stale or tampered list fails there rather than being trusted from the client.
      waivers: {:accepted, List.wrap(params["waiver_version_ids"])},
      audit: socket.assigns.audit
    }

    Enrollment.create_enrollment(enrollment_params)
  end

  # Prefilling special requirements from the child is only correct when the child
  # actually changed — doing it on every form change would discard what the parent typed.
  defp select_child(socket, child_id) do
    child = Map.get(socket.assigns.children_by_id, child_id)

    eligibility =
      case Enrollment.check_participant_eligibility(socket.assigns.program.id, child_id) do
        {:ok, :eligible} -> :eligible
        {:error, :ineligible, reasons} -> {:ineligible, reasons}
        _ -> :eligible
      end

    assign(socket,
      selected_child_id: child_id,
      special_requirements: build_special_requirements(child),
      eligibility_status: eligibility
    )
  end

  defp build_special_requirements(nil), do: ""

  defp build_special_requirements(child) do
    [child.allergies, child.support_needs]
    |> Enum.reject(&(is_nil(&1) or String.trim(&1) == ""))
    |> Enum.join("\n")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["min-h-screen", Theme.gradient(:hero)]}>
      <div class="max-w-4xl mx-auto px-4 py-6">
        <.page_header
          variant={:gradient}
          show_back_button
          phx-click="back_to_program"
          class="!p-0 !bg-transparent !shadow-none mb-6"
        >
          <:title>
            <h1 class={[Theme.typography(:page_title), "text-white"]}>{gettext("Enrollment")}</h1>
          </:title>
        </.page_header>

        <div class="mb-6">
          <h3 class="text-white font-semibold mb-3">{gettext("Activity Summary")}</h3>
          <div class={[Theme.bg(:surface), Theme.rounded(:xl), "p-6 shadow-lg"]}>
            <div class="flex gap-4 mb-4">
              <div class={[
                "w-16 h-16 flex items-center justify-center text-3xl",
                Theme.rounded(:lg),
                Theme.gradient(:hero)
              ]}>
                🎨
              </div>
              <div>
                <h4 class={[Theme.typography(:card_title), "mb-1", Theme.text_color(:heading)]}>
                  {@program.title}
                </h4>
                <p
                  :if={@schedule_brief != ""}
                  class={["text-sm", Theme.text_color(:secondary)]}
                >
                  {@schedule_brief}
                </p>
              </div>
            </div>
            <div class={["border-t pt-4", Theme.border_color(:medium)]}>
              <div class="flex justify-between items-center mb-2">
                <span class={["font-semibold", Theme.text_color(:body)]}>
                  {gettext("Total Price:")}
                </span>
                <span class={[Theme.typography(:section_title), Theme.text_color(:primary)]}>
                  {ProgramPresenter.price_label(@total_amount)}
                </span>
              </div>
              <div class="flex justify-between text-sm">
                <span class={Theme.text_color(:secondary)}>{gettext("Duration:")}</span>
                <span class={Theme.text_color(:secondary)}>
                  {ProgramPresenter.format_date_range_brief(@program) || gettext("TBD")}
                </span>
              </div>
            </div>
          </div>
          <div class="mt-2">
            <a href="#" class="text-xs text-white/80 hover:text-white underline">
              {gettext("Add another program")}
            </a>
          </div>
        </div>

        <form
          id="booking-form"
          phx-change="booking_form_changed"
          phx-submit="complete_enrollment"
          class="space-y-6"
        >
          <div class={[Theme.bg(:surface), Theme.rounded(:xl), "p-6 shadow-lg"]}>
            <label
              for="booking-child-select"
              class={["block text-sm font-semibold mb-3", Theme.text_color(:body)]}
            >
              {gettext("Select Child")}
            </label>
            <select
              id="booking-child-select"
              name="child_id"
              class={[
                "w-full px-4 py-3 border border-hero-grey-300 focus:ring-2 focus:ring-[var(--focus-ring)] focus:border-transparent",
                Theme.rounded(:lg)
              ]}
            >
              <option value="">{gettext("Select a child")}</option>
              <option
                :for={child <- @children}
                value={child.id}
                selected={child.id == @selected_child_id}
              >
                {gettext("%{name} (Age %{age})", name: child.name, age: child.age)}
              </option>
            </select>
            <.eligibility_status :if={@selected_child_id} status={@eligibility_status} />
            <div class="mt-2">
              <a
                href="#"
                class={[
                  "text-xs underline",
                  Theme.text_color(:muted),
                  "hover:#{Theme.text_color(:body)}"
                ]}
              >
                {gettext("Add another child")}
              </a>
            </div>
          </div>

          <div class={[Theme.bg(:surface), Theme.rounded(:xl), "p-6 shadow-lg"]}>
            <label
              for="special-requirements"
              class={["block text-sm font-semibold mb-3", Theme.text_color(:body)]}
            >
              {gettext("Special Requirements")}
            </label>
            <textarea
              id="special-requirements"
              name="special_requirements"
              rows="3"
              maxlength="500"
              placeholder={gettext("Any allergies, medical conditions, or special instructions...")}
              class={[
                "w-full px-4 py-3 border border-hero-grey-300 focus:ring-2 focus:ring-[var(--focus-ring)] focus:border-transparent resize-none",
                Theme.rounded(:lg)
              ]}
            >{@special_requirements}</textarea>
            <div class="flex justify-between mt-2">
              <p class={["text-xs", Theme.text_color(:muted)]}>
                {gettext(
                  "Optional: Include any important information we should know about your child."
                )}
              </p>
              <p class={["text-xs", Theme.text_color(:muted)]}>0/500</p>
            </div>
          </div>

          <div
            :if={@waivers != []}
            id="booking-waivers"
            class={[Theme.bg(:surface), Theme.rounded(:xl), "p-6 shadow-lg"]}
          >
            <h2 class={["block text-sm font-semibold mb-3", Theme.text_color(:body)]}>
              {gettext("Waivers")}
            </h2>

            <div :for={entry <- @waivers} id={"waiver-#{entry.waiver.id}"} class="mb-4 last:mb-0">
              <h3 class={[
                Theme.typography(:card_title),
                Theme.text_color(:heading),
                "mb-2 flex flex-wrap items-center gap-2"
              ]}>
                {entry.waiver.title}
                <.waiver_requirement required={entry.waiver.required} />
              </h3>

              <%!-- Scrollable rather than truncated: a parent must be able to read the whole
                    text before signing, and a "read more" that collapses it would weaken the
                    claim that they saw it. --%>
              <div
                class={[
                  "max-h-48 overflow-y-auto border p-3 text-sm whitespace-pre-line mb-2",
                  Theme.rounded(:lg),
                  Theme.border_color(:medium),
                  Theme.text_color(:body)
                ]}
                tabindex="0"
              >
                {entry.version.body}
              </div>

              <label class="flex items-start gap-2 text-sm cursor-pointer">
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
          </div>

          <div class={[Theme.bg(:surface), Theme.rounded(:xl), "p-6 shadow-lg"]}>
            <fieldset>
              <legend class={["block text-sm font-semibold mb-3", Theme.text_color(:body)]}>
                {gettext("Payment Method")}
              </legend>
              <div class="space-y-3">
                <.payment_option
                  value="card"
                  title={gettext("Credit Card")}
                  description={gettext("Pay securely with Visa, Mastercard, or other cards")}
                  selected={@payment_method == "card"}
                  phx-click="select_payment_method"
                  phx-value-method="card"
                />

                <.payment_option
                  value="transfer"
                  title={gettext("Cash / Bank Transfer")}
                  description={gettext("Pay by cash or direct bank transfer")}
                  selected={@payment_method == "transfer"}
                  phx-click="select_payment_method"
                  phx-value-method="transfer"
                />
              </div>
            </fieldset>
          </div>

          <.booking_summary id="payment-summary" title={gettext("Payment Summary")}>
            <:line_item
              label={gettext("Program fee:")}
              value={ProgramPresenter.price_label(@total_amount)}
            />
            <:total
              label={gettext("Total due today:")}
              value={ProgramPresenter.price_label(@total_amount)}
            />
          </.booking_summary>

          <.info_box variant={:neutral} icon="📧" title={gettext("Invoice & Payment Confirmation")}>
            <div class="text-sm space-y-1">
              <p>• {gettext("An invoice will be emailed to you after enrollment completion")}</p>
              <p>• {gettext("Credit card payments are processed immediately")}</p>
              <p>• {gettext("Cash/transfer payments will show as \"Pending\" until received")}</p>
            </div>
          </.info_box>

          <button
            type="submit"
            disabled={match?({:ineligible, _}, @eligibility_status)}
            class={[
              "w-full py-4 text-white",
              Theme.typography(:card_title),
              Theme.rounded(:lg),
              "hover:shadow-lg transform hover:scale-[1.02]",
              Theme.transition(:normal),
              Theme.gradient(:primary),
              match?({:ineligible, _}, @eligibility_status) && "opacity-50 cursor-not-allowed"
            ]}
          >
            {gettext("Complete Enrollment")}
          </button>
        </form>
      </div>
    </div>
    """
  end
end
