defmodule KlassHeroWeb.UserLive.Settings do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.MarketingComponents

  alias KlassHero.Accounts
  alias KlassHeroWeb.Helpers.FamilyHelpers
  alias KlassHeroWeb.Presenters.ChildPresenter

  on_mount {KlassHeroWeb.UserAuth, :require_sudo_mode}

  @impl true
  def render(assigns) do
    ~H"""
    <.mk_page_hero pill={gettext("Account")}>
      <:title>
        <span class="bg-hero-yellow-500 px-2 rounded-lg">{gettext("Account")}</span>
        {gettext("settings")}
      </:title>
      <:lede>{gettext("Manage your account, preferences, and privacy in one place.")}</:lede>
    </.mk_page_hero>

    <section class="relative pb-20 -mt-8 lg:-mt-12 px-6">
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
                <div class="flex flex-wrap gap-3">
                  <label class={[
                    "flex items-center gap-2 px-4 py-3 rounded-xl border-2 cursor-pointer transition-colors",
                    if(@current_scope.user.locale == "en",
                      do: "border-[var(--brand-primary)] bg-hero-pink-50",
                      else: "border-[var(--border-light)] hover:border-[var(--border-medium)]"
                    )
                  ]}>
                    <input
                      type="radio"
                      name="user[locale]"
                      value="en"
                      checked={@current_scope.user.locale == "en"}
                      class="hidden"
                    />
                    <span class="text-2xl">🇬🇧</span>
                    <span class="font-semibold text-hero-black">{gettext("English")}</span>
                  </label>

                  <label class={[
                    "flex items-center gap-2 px-4 py-3 rounded-xl border-2 cursor-pointer transition-colors",
                    if(@current_scope.user.locale == "de",
                      do: "border-[var(--brand-primary)] bg-hero-pink-50",
                      else: "border-[var(--border-light)] hover:border-[var(--border-medium)]"
                    )
                  ]}>
                    <input
                      type="radio"
                      name="user[locale]"
                      value="de"
                      checked={@current_scope.user.locale == "de"}
                      class="hidden"
                    />
                    <span class="text-2xl">🇩🇪</span>
                    <span class="font-semibold text-hero-black">{gettext("Deutsch")}</span>
                  </label>
                </div>
              </.form>
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
      <.icon name={@icon} class="w-4 h-4 text-[var(--brand-primary-dark)]" />
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
      |> assign(:active_nav, :auth)
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:locale_form, to_form(locale_changeset))
      |> assign(:delete_form, to_form(%{"password" => ""}, as: :delete))
      |> assign(:trigger_submit, false)
      |> assign(:user_initials, get_user_initials(user.email))
      |> assign(:member_since, format_member_since(user.inserted_at))
      |> assign(:children_summary, ChildPresenter.children_summary(children))

    {:ok, socket}
  end

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
