defmodule KlassHeroWeb.ContactLive do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.MarketingComponents

  alias KlassHeroWeb.Schemas.ContactForm

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    changeset = ContactForm.changeset(%ContactForm{}, prefill_attrs(socket.assigns.current_scope))

    socket =
      socket
      |> assign(page_title: gettext("Contact Us"))
      |> assign(active_nav: :contact)
      |> assign(form: to_form(changeset, as: :contact))
      |> assign(submission_status: nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"contact" => contact_params}, socket) do
    changeset =
      %ContactForm{}
      |> ContactForm.changeset(contact_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :contact))}
  end

  @impl true
  def handle_event("submit", %{"contact" => contact_params}, socket) do
    changeset = ContactForm.changeset(%ContactForm{}, contact_params)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, validated_form} ->
        Logger.info("Contact form submitted",
          name: validated_form.name,
          email: validated_form.email,
          subject: validated_form.subject
        )

        {:noreply,
         socket
         |> assign(submission_status: :success)
         |> assign(form: to_form(ContactForm.changeset(%ContactForm{}, %{}), as: :contact))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :contact))}
    end
  end

  # Seeds the contact form's initial name/email from the signed-in user, so
  # logged-in visitors don't retype what we already know. On the public /contact
  # route `current_scope.user` is nil for anonymous visitors — seed nothing then.
  defp prefill_attrs(%{user: %{} = user}), do: %{"name" => user.name, "email" => user.email}
  defp prefill_attrs(_scope), do: %{}

  defp contact_methods do
    email = KlassHero.Contact.email()
    phone = KlassHero.Contact.phone()
    address = KlassHero.Contact.address()

    [
      email &&
        %{
          icon: "hero-envelope",
          title: gettext("Email"),
          value: email,
          note: nil
        },
      phone &&
        %{
          icon: "hero-phone",
          title: gettext("Phone"),
          value: phone,
          note: nil
        },
      address &&
        %{
          icon: "hero-map-pin",
          title: gettext("Address"),
          value: address,
          note: nil
        }
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp subject_options do
    [
      {gettext("General Inquiry"), "general"},
      {gettext("Program Question"), "program"},
      {gettext("Booking Support"), "booking"},
      {gettext("Instructor Application"), "instructor"},
      {gettext("Technical Issue"), "technical"},
      {gettext("Other"), "other"}
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.mk_page_hero id="mk-contact-hero" pill={gettext("Contact Us")}>
      <:title>
        {gettext("We're here to")}
        <span class="bg-hero-yellow-500 px-2 rounded-lg">{gettext("help")}</span>
      </:title>
      <:lede>
        {gettext("Questions about programs, bookings, or becoming a Hero — we read every message.")}
      </:lede>
    </.mk_page_hero>

    <section id="mk-contact-body" class="py-12 lg:py-16 bg-white">
      <div class="max-w-6xl mx-auto px-6 grid md:grid-cols-[1.1fr_0.9fr] gap-8 items-start">
        <.kh_card class="p-7 lg:p-9">
          <%!-- typography-lint-ignore: form-card title in display font --%>
          <h2 class="font-display font-bold tracking-tight text-3xl text-hero-black">
            {gettext("Send us a message")}
          </h2>
          <p class="text-[var(--fg-muted)] mt-1.5">
            {gettext("Tell us a bit about what you need — we'll route you to the right person.")}
          </p>

          <div
            :if={@submission_status == :success}
            class="mt-6 p-4 rounded-xl bg-hero-blue-50 border border-hero-blue-200 flex items-start gap-3"
          >
            <.icon name="hero-check-circle" class="w-5 h-5 text-hero-blue-600 mt-0.5" />
            <div>
              <div class="font-semibold text-hero-blue-700">
                {gettext("Message sent successfully!")}
              </div>
              <div class="text-sm text-[var(--fg-muted)] mt-0.5">
                {gettext("We've got it — we'll be in touch.")}
              </div>
            </div>
          </div>

          <.form
            for={@form}
            id="contact-form"
            phx-change="validate"
            phx-submit="submit"
            class="mt-6 space-y-4"
          >
            <div class="grid sm:grid-cols-2 gap-4">
              <.mk_input
                field={@form[:name]}
                label={gettext("Name")}
                placeholder="Anna Schmidt"
                required
              />
              <.mk_input
                field={@form[:email]}
                type="email"
                label={gettext("Email")}
                placeholder="anna@example.com"
                required
              />
            </div>
            <.mk_input
              field={@form[:subject]}
              type="select"
              label={gettext("Subject")}
              prompt={gettext("Select a topic…")}
              options={subject_options()}
              required
            />
            <.mk_input
              field={@form[:message]}
              type="textarea"
              label={gettext("Message")}
              placeholder={gettext("What's on your mind?")}
              required
            />

            <div class="flex items-center justify-between flex-wrap gap-3 pt-2">
              <div class="text-xs text-[var(--fg-muted)] flex items-center gap-1.5">
                <.icon name="hero-shield-check" class="w-4 h-4" />
                {gettext("We never share your details.")}
              </div>
              <.kh_button type="submit" variant={:primary} size={:lg}>
                {gettext("Send Message →")}
              </.kh_button>
            </div>
          </.form>
        </.kh_card>

        <div class="space-y-4">
          <.kh_card class="p-6">
            <h3 class="font-bold text-lg text-hero-black mb-4">{gettext("Get in touch")}</h3>
            <div class="space-y-3">
              <.mk_method_row
                :for={method <- contact_methods()}
                icon={method.icon}
                title={method.title}
                value={method.value}
                note={method.note}
              />
            </div>
          </.kh_card>

          <.kh_card class="p-6 bg-gradient-to-br from-hero-blue-50 to-white">
            <div class="flex items-start gap-4">
              <.kh_icon_chip icon="hero-sparkles" gradient={:comic} size={:md} />
              <div>
                <h3 class="font-bold text-hero-black">
                  {gettext("Looking for quick answers?")}
                </h3>
                <p class="text-sm text-[var(--fg-muted)] mt-1">
                  {gettext("Check our FAQ — most questions are answered there.")}
                </p>
                <.link
                  href={~p"/" <> "#mk-faq"}
                  class={
                    [
                      "inline-block mt-3 text-[var(--fg-link)]",
                      # typography-lint-ignore: marketing accent link uses display font for visual emphasis
                      "font-display font-bold"
                    ]
                  }
                >
                  {gettext("Visit FAQ →")}
                </.link>
              </div>
            </div>
          </.kh_card>
        </div>
      </div>
    </section>
    """
  end
end
