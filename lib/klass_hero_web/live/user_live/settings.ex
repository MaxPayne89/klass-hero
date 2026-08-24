defmodule KlassHeroWeb.UserLive.Settings do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.MarketingComponents, only: [mk_input: 1]

  alias KlassHero.Accounts
  alias KlassHeroWeb.Helpers.FamilyHelpers
  alias KlassHeroWeb.Layouts
  alias KlassHeroWeb.Locale
  alias KlassHeroWeb.Persona
  alias KlassHeroWeb.Presenters.ChildPresenter

  require Logger

  on_mount {KlassHeroWeb.UserAuth, :require_sudo_mode}

  @impl true
  def render(assigns) do
    ~H"""
    <section class="relative pb-20 px-0 lg:px-6">
      <div class="max-w-6xl mx-auto lg:flex lg:gap-8 items-start">
        <%!-- Sticky sidebar nav (desktop) --%>
        <aside class="hidden lg:block lg:w-60 lg:flex-shrink-0 sticky top-24">
          <.kh_card class="overflow-hidden">
            <div class="p-4 border-b border-[var(--border-light)]">
              <h3 class="font-semibold text-sm text-[var(--fg-muted)]">
                {gettext("Quick Navigation")}
              </h3>
            </div>
            <nav class="py-2">
              <.settings_nav_link icon="hero-user-circle" title={gettext("Profile")} href="#profile" />
              <.settings_nav_link
                icon="hero-user-group"
                title={gettext("Children")}
                navigate={~p"/settings/children"}
              />
              <.settings_nav_link
                :if={@addable_personas != []}
                icon="hero-identification"
                title={gettext("Profiles")}
                href="#profiles"
              />
              <.settings_nav_link
                icon="hero-shield-check"
                title={gettext("Security")}
                href="#security"
              />
              <.settings_nav_link
                icon="hero-globe-alt"
                title={gettext("Preferences")}
                href="#preferences"
              />
              <.settings_nav_link
                icon="hero-document-text"
                title={gettext("Data & privacy")}
                href="#data-privacy"
              />
            </nav>
          </.kh_card>
        </aside>

        <div class="flex-1 space-y-6 mt-6 lg:mt-0">
          <%!-- Profile --%>
          <.kh_card id="profile" class="p-5">
            <div class="flex items-center gap-4">
              <%!-- typography-lint-ignore: avatar initials uses display font as visual emphasis --%>
              <div class="w-16 h-16 rounded-full bg-gradient-to-br from-hero-blue-400 to-hero-blue-600 text-white flex items-center justify-center text-xl font-display font-extrabold">
                {@user_initials}
              </div>
              <div>
                <h2 class="font-bold text-lg text-hero-black">{@current_scope.user.email}</h2>
                <p class="text-sm text-[var(--fg-muted)]">
                  {gettext("Member since")} {@member_since}
                </p>
              </div>
            </div>
          </.kh_card>

          <%!-- Account Security --%>
          <.kh_card id="security" class="overflow-hidden">
            <div class="p-5 border-b border-[var(--border-light)] flex items-center gap-3">
              <.kh_icon_chip icon="hero-shield-check" gradient={:cool} size={:sm} />
              <div>
                <h2 class="font-bold text-hero-black">{gettext("Account Security")}</h2>
                <p class="text-sm text-[var(--fg-muted)]">
                  {gettext("Manage your email and password")}
                </p>
              </div>
            </div>
            <div class="p-5 space-y-6">
              <div>
                <h3 class="text-sm font-semibold mb-3 text-hero-black">
                  {gettext("Email Address")}
                </h3>
                <.form
                  for={@email_form}
                  id="email_form"
                  phx-submit="update_email"
                  phx-change="validate_email"
                  class="max-w-md space-y-4"
                >
                  <.mk_input
                    field={@email_form[:email]}
                    type="email"
                    label={gettext("Email")}
                    autocomplete="username"
                    required
                  />
                  <.kh_button
                    type="submit"
                    variant={:primary}
                    phx-disable-with={gettext("Changing...")}
                  >
                    {gettext("Change Email")}
                  </.kh_button>
                </.form>
              </div>

              <div class="border-t border-[var(--border-light)]" />

              <div>
                <h3 class="text-sm font-semibold mb-3 text-hero-black">{gettext("Password")}</h3>
                <.form
                  for={@password_form}
                  id="password_form"
                  action={~p"/users/update-password"}
                  method="post"
                  phx-change="validate_password"
                  phx-submit="update_password"
                  phx-trigger-action={@trigger_submit}
                  class="max-w-md space-y-4"
                >
                  <input
                    name={@password_form[:email].name}
                    type="hidden"
                    id="hidden_user_email"
                    autocomplete="username"
                    value={@current_email}
                  />
                  <.mk_input
                    field={@password_form[:password]}
                    type="password"
                    label={gettext("New password")}
                    autocomplete="new-password"
                    required
                  />
                  <.mk_input
                    field={@password_form[:password_confirmation]}
                    type="password"
                    label={gettext("Confirm new password")}
                    autocomplete="new-password"
                  />
                  <.kh_button type="submit" variant={:primary} phx-disable-with={gettext("Saving...")}>
                    {gettext("Save Password")}
                  </.kh_button>
                </.form>
              </div>
            </div>
          </.kh_card>

          <%!-- Preferences --%>
          <.kh_card id="preferences" class="overflow-hidden">
            <div class="p-5 border-b border-[var(--border-light)] flex items-center gap-3">
              <.kh_icon_chip icon="hero-globe-alt" gradient={:art} size={:sm} />
              <div>
                <h2 class="font-bold text-hero-black">{gettext("Preferences")}</h2>
                <p class="text-sm text-[var(--fg-muted)]">{gettext("Customize your experience")}</p>
              </div>
            </div>
            <div class="p-5">
              <h3 class="text-sm font-semibold mb-3 text-hero-black">
                {gettext("Language Preference")}
              </h3>
              <p class="text-sm mb-4 text-[var(--fg-muted)]">
                {gettext("Choose your preferred language for the interface")}
              </p>
              <.form for={@locale_form} id="locale_form" phx-change="update_locale">
                <%!-- Labels are endonyms, so they are not translated — see
                      KlassHeroWeb.Locale. --%>
                <div class="flex flex-wrap gap-3">
                  <label
                    :for={locale <- Locale.supported()}
                    id={"locale-option-#{locale}"}
                    class={[
                      "flex items-center gap-2 px-4 py-3 rounded-xl border-2 cursor-pointer transition-colors",
                      if(@current_scope.user.locale == locale,
                        do: "border-[var(--brand-primary)] bg-hero-pink-50",
                        else: "border-[var(--border-light)] hover:border-[var(--border-medium)]"
                      )
                    ]}
                  >
                    <input
                      type="radio"
                      name="user[locale]"
                      value={locale}
                      checked={@current_scope.user.locale == locale}
                      class="hidden"
                    />
                    <span class="text-2xl">{Locale.flag(locale)}</span>
                    <span class="font-semibold text-hero-black">{Locale.label(locale)}</span>
                  </label>
                </div>
              </.form>
            </div>
          </.kh_card>

          <%!-- Profiles --%>
          <.kh_card :if={@addable_personas != []} id="profiles" class="overflow-hidden">
            <div class="p-5 border-b border-[var(--border-light)] flex items-center gap-3">
              <.kh_icon_chip icon="hero-identification" gradient={:primary} size={:sm} />
              <div>
                <h2 class="font-bold text-hero-black">{gettext("Profiles")}</h2>
                <p class="text-sm text-[var(--fg-muted)]">
                  {gettext("One account can be both a family and a provider.")}
                </p>
              </div>
            </div>
            <div class="p-5 space-y-3">
              <div
                :for={persona <- @addable_personas}
                id={"add-#{persona}-profile"}
                class="p-4 rounded-xl border border-[var(--border-light)]"
              >
                <%= if @confirming_persona == persona do %>
                  <p class="text-sm text-[var(--fg-muted)]">
                    {persona_confirm_copy(persona)}
                  </p>
                  <div class="flex flex-col sm:flex-row gap-2 mt-4">
                    <.kh_button
                      id={"add-#{persona}-profile-confirm"}
                      variant={:primary}
                      class="w-full sm:w-auto justify-center"
                      phx-click="confirm_persona"
                      phx-value-persona={persona}
                      phx-disable-with={gettext("Setting up...")}
                    >
                      {persona_confirm_label(persona)}
                    </.kh_button>
                    <.kh_button
                      id={"add-#{persona}-profile-cancel"}
                      variant={:ghost}
                      class="w-full sm:w-auto justify-center"
                      phx-click="cancel_persona"
                    >
                      {gettext("Not now")}
                    </.kh_button>
                  </div>
                <% else %>
                  <div class="flex items-center justify-between gap-3">
                    <div class="flex items-center gap-3 min-w-0">
                      <.kh_icon_chip
                        icon={persona_icon(persona)}
                        gradient={:cool}
                        size={:sm}
                      />
                      <div class="min-w-0">
                        <p class="font-semibold text-hero-black">
                          {persona_add_label(persona)}
                        </p>
                        <p class="text-sm text-[var(--fg-muted)]">
                          {persona_add_description(persona)}
                        </p>
                      </div>
                    </div>
                    <.kh_button
                      id={"add-#{persona}-profile-button"}
                      variant={:primary}
                      size={:sm}
                      class="shrink-0"
                      phx-click="request_persona"
                      phx-value-persona={persona}
                    >
                      {gettext("Add")}
                    </.kh_button>
                  </div>
                <% end %>
              </div>
            </div>
          </.kh_card>

          <%!-- My Family --%>
          <.kh_card id="my-family" class="overflow-hidden">
            <div class="p-5 border-b border-[var(--border-light)] flex items-center gap-3">
              <.kh_icon_chip icon="hero-user-group" gradient={:primary} size={:sm} />
              <div>
                <h2 class="font-bold text-hero-black">{gettext("My Family")}</h2>
                <p class="text-sm text-[var(--fg-muted)]">
                  {gettext("Manage your children's profiles")}
                </p>
              </div>
            </div>
            <div class="p-5">
              <.link
                navigate={~p"/settings/children"}
                class="flex items-center justify-between p-4 rounded-xl border border-[var(--border-light)] hover:bg-hero-cream-100 transition-colors"
              >
                <div class="flex items-center gap-3">
                  <.kh_icon_chip icon="hero-user-group" gradient={:primary} size={:sm} />
                  <div>
                    <p class="font-semibold text-hero-black">{gettext("Children Profiles")}</p>
                    <p class="text-sm text-[var(--fg-muted)]">{@children_summary}</p>
                  </div>
                </div>
                <.icon name="hero-chevron-right" class="w-5 h-5 text-[var(--fg-muted)]" />
              </.link>
            </div>
          </.kh_card>

          <%!-- Data & Privacy --%>
          <.kh_card id="data-privacy" class="overflow-hidden">
            <div class="p-5 border-b border-[var(--border-light)] flex items-center gap-3">
              <.kh_icon_chip icon="hero-document-text" gradient={:dark} size={:sm} />
              <div>
                <h2 class="font-bold text-hero-black">{gettext("Data & Privacy")}</h2>
                <p class="text-sm text-[var(--fg-muted)]">
                  {gettext("Download your data or delete your account")}
                </p>
              </div>
            </div>
            <div class="p-5 space-y-6">
              <div>
                <h3 class="text-sm font-semibold mb-2 text-hero-black">{gettext("Your Data")}</h3>
                <p class="text-sm mb-4 text-[var(--fg-muted)]">
                  {gettext("Download a copy of all your personal data")}
                </p>
                <.link href={~p"/users/export-data"}>
                  <.kh_button variant={:ghost} icon="hero-arrow-down-tray">
                    {gettext("Download My Data")}
                  </.kh_button>
                </.link>
              </div>

              <div class="flex items-center gap-3">
                <div class="flex-1 border-t border-[var(--error)]/30" />
                <span class="text-xs font-bold text-[var(--error)] uppercase tracking-wide">
                  {gettext("Danger Zone")}
                </span>
                <div class="flex-1 border-t border-[var(--error)]/30" />
              </div>

              <div class="bg-[var(--error-bg)] rounded-xl p-5 border border-[var(--error)]/20">
                <h3 class="text-sm font-bold mb-2 text-[var(--error)]">
                  {gettext("Delete Account")}
                </h3>
                <p class="text-sm text-[var(--error)]/80 mb-4">
                  {gettext(
                    "This action cannot be undone. Your account data will be anonymized and you will be logged out."
                  )}
                </p>
                <.form
                  for={@delete_form}
                  id="delete_account_form"
                  phx-submit="delete_account"
                  class="max-w-md space-y-4"
                >
                  <.mk_input
                    field={@delete_form[:password]}
                    type="password"
                    label={gettext("Enter your password to confirm")}
                    autocomplete="current-password"
                    required
                  />
                  <button
                    type="submit"
                    phx-disable-with={gettext("Deleting...")}
                    class={
                      [
                        "inline-flex items-center justify-center gap-2 px-5 py-3 text-[15px] rounded-xl",
                        # typography-lint-ignore: destructive-action button mirrors KhButton primary surface on error tone
                        "font-display font-bold tracking-tight",
                        "bg-[var(--error)] text-white hover:opacity-90 transition-all cursor-pointer"
                      ]
                    }
                  >
                    {gettext("Delete My Account")}
                  </button>
                </.form>
              </div>
            </div>
          </.kh_card>
        </div>
      </div>
    </section>
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :href, :string, default: nil
  attr :navigate, :string, default: nil

  defp settings_nav_link(assigns) do
    ~H"""
    <.link
      href={@href}
      navigate={@navigate}
      class="flex items-center gap-3 px-4 py-2.5 hover:bg-hero-cream-100 transition-colors"
    >
      <.icon name={@icon} class="w-4 h-4 text-[var(--fg-link)]" />
      <span class="text-sm font-semibold text-hero-black">{@title}</span>
    </.link>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, gettext("Email changed successfully."))

        {:error, _} ->
          put_flash(socket, :error, gettext("Email change link is invalid or it has expired."))
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)
    locale_changeset = Accounts.change_user_locale(user, %{})
    children = FamilyHelpers.get_children_for_current_user(socket)

    socket =
      socket
      |> assign(:active_nav, :settings)
      |> assign(:page_title, gettext("Settings"))
      |> assign(:page_subtitle, gettext("Manage your account, preferences, and privacy."))
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:locale_form, to_form(locale_changeset))
      |> assign(:delete_form, to_form(%{"password" => ""}, as: :delete))
      |> assign(:trigger_submit, false)
      |> assign(:user_initials, get_user_initials(user.email))
      |> assign(:member_since, format_member_since(user.inserted_at))
      |> assign(:children_summary, ChildPresenter.children_summary(children))
      |> assign(:confirming_persona, nil)
      |> assign(:addable_personas, addable_personas(socket.assigns.current_scope))

    {:ok, socket, layout: layout_for(socket.assigns[:active_persona])}
  end

  # Settings used to render in the marketing layout — the only authenticated
  # non-admin page that did. Arriving from the account menu therefore dropped you
  # out of your own app shell, and on mobile stranded you: the marketing header's
  # only way back is `hidden lg:inline-flex`, and kh_user_menu is not rendered on
  # marketing pages at all. Following the persona restores the sidebar, the
  # bottom tabs and the switcher on the very page that grants a second persona.
  defp layout_for(:provider), do: {Layouts, :provider_app}
  defp layout_for(:staff), do: {Layouts, :provider_app}
  defp layout_for(_persona), do: {Layouts, :parent_app}

  # Only these two are self-grantable. :staff is an employment link to someone
  # else's business (ADR-0005) — a provider adds themselves to their own team
  # from the team page, and nobody can hire themselves into another's.
  @self_grantable [:parent, :provider]

  defp addable_personas(scope), do: @self_grantable -- Persona.available(scope)

  defp add_persona(socket, :parent) do
    case Accounts.upgrade_to_parent(socket.assigns.current_scope.user) do
      {:ok, _user} ->
        socket
        |> put_flash(:info, gettext("Family profile added. You can add your children now."))
        |> push_navigate(to: ~p"/settings/children")

      # Stale tab: added elsewhere. Re-converge rather than reporting a failure.
      {:error, :already_parent} ->
        socket
        |> put_flash(:info, gettext("You already have a family profile."))
        |> push_navigate(to: ~p"/users/settings")

      {:error, reason} ->
        persona_failed(socket, :parent, reason)
    end
  end

  defp add_persona(socket, :provider) do
    case Accounts.upgrade_to_provider(socket.assigns.current_scope.user) do
      {:ok, _user} ->
        socket
        |> put_flash(:info, gettext("Welcome aboard! Let's set up your provider profile."))
        |> push_navigate(to: ~p"/provider/complete-profile")

      {:error, :already_provider} ->
        socket
        |> put_flash(:info, gettext("You already have a provider profile."))
        |> push_navigate(to: ~p"/users/settings")

      {:error, reason} ->
        persona_failed(socket, :provider, reason)
    end
  end

  # A persona this account already holds has no button, so reaching here means a
  # crafted event; treat it as a no-op rather than dispatching on nil.
  defp add_persona(socket, _persona), do: assign(socket, :confirming_persona, nil)

  defp persona_failed(socket, persona, reason) do
    # Log the reason only: a changeset's :changes carries the user's name and
    # email, which Inspect does not redact.
    Logger.error("Failed to add #{persona} profile",
      user_id: socket.assigns.current_scope.user.id,
      reason: inspect(reason)
    )

    socket
    |> assign(:confirming_persona, nil)
    |> put_flash(:error, gettext("Something went wrong. Please try again."))
  end

  defp persona_icon(:parent), do: "hero-user-group"
  defp persona_icon(:provider), do: "hero-building-storefront"

  defp persona_add_label(:parent), do: gettext("Add a family profile")
  defp persona_add_label(:provider), do: gettext("Add a provider profile")

  defp persona_add_description(:parent), do: gettext("Book activities and manage your children's places.")

  defp persona_add_description(:provider), do: gettext("List your own activities and take bookings.")

  defp persona_confirm_copy(:parent),
    do:
      gettext("You'll be able to add your children and book activities. Your provider account stays exactly as it is.")

  defp persona_confirm_copy(:provider),
    do:
      gettext(
        "You'll get a provider profile to fill in, and a dashboard for your activities. Your family account stays exactly as it is."
      )

  defp persona_confirm_label(:parent), do: gettext("Add family profile")
  defp persona_confirm_label(:provider), do: gettext("Add provider profile")

  defp get_user_initials(email) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.slice(0, 2)
    |> String.upcase()
  end

  defp get_user_initials(_), do: "?"

  defp format_member_since(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%B %Y")
  end

  defp format_member_since(_), do: ""

  @impl true
  def handle_event("request_persona", %{"persona" => persona}, socket) do
    {:noreply, assign(socket, :confirming_persona, Persona.validate(persona))}
  end

  @impl true
  def handle_event("cancel_persona", _params, socket) do
    {:noreply, assign(socket, :confirming_persona, nil)}
  end

  @impl true
  def handle_event("confirm_persona", %{"persona" => persona}, socket) do
    {:noreply, add_persona(socket, Persona.validate(persona))}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user

    if Accounts.sudo_mode?(user) do
      case Accounts.change_user_email(user, user_params) do
        %{valid?: true} = changeset ->
          Accounts.deliver_user_update_email_instructions(
            Ecto.Changeset.apply_action!(changeset, :insert),
            user.email,
            &url(~p"/users/settings/confirm-email/#{&1}")
          )

          info = gettext("A link to confirm your email change has been sent to the new address.")
          {:noreply, socket |> put_flash(:info, info)}

        changeset ->
          {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, gettext("Please re-authenticate to change your email."))
       |> redirect(to: ~p"/users/log-in")}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user

    if Accounts.sudo_mode?(user) do
      case Accounts.change_user_password(user, user_params) do
        %{valid?: true} = changeset ->
          {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

        changeset ->
          {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, gettext("Please re-authenticate to change your password."))
       |> redirect(to: ~p"/users/log-in")}
    end
  end

  # Handing this to the controller rather than writing it here is the whole fix
  # for #1161: only the plug pipeline can write the session that SetLocale reads
  # first, and only its redirect re-renders the root layout's <html lang>.
  def handle_event("update_locale", %{"user" => %{"locale" => locale}}, socket) do
    {:noreply, redirect(socket, to: ~p"/locale/#{locale}?return_to=/users/settings")}
  end

  def handle_event("delete_account", %{"delete" => %{"password" => password}}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.delete_account(user, password) do
      {:ok, _anonymized_user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Your account has been deleted."))
         |> redirect(to: ~p"/")}

      {:error, :sudo_required} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Please re-authenticate to delete your account."))
         |> redirect(to: ~p"/users/log-in")}

      {:error, :invalid_password} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Invalid password."))
         |> assign(:delete_form, to_form(%{"password" => ""}, as: :delete))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Failed to delete account. Please try again."))
         |> assign(:delete_form, to_form(%{"password" => ""}, as: :delete))}
    end
  end
end
