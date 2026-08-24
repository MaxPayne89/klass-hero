defmodule KlassHeroWeb.UserLive.Registration do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.MarketingComponents

  alias KlassHero.Accounts
  alias KlassHero.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <.mk_page_hero pill={gettext("Sign up")}>
      <:title>
        {gettext("Create your")}
        <span class="bg-hero-yellow-500 px-2 rounded-lg">{gettext("account")}</span>
      </:title>
      <:lede>
        {gettext("Already registered?")}
        <.link
          navigate={~p"/users/log-in"}
          class="font-bold text-[var(--brand-primary-dark)] hover:underline"
        >
          {gettext("Log in")}
        </.link>
      </:lede>
    </.mk_page_hero>

    <section class="relative pb-20 -mt-8 lg:-mt-12 px-6">
      <div class="max-w-md mx-auto">
        <.kh_card class="p-7 lg:p-9">
          <.form
            for={@form}
            id="registration_form"
            phx-submit="save"
            phx-change="validate"
            class="space-y-4"
          >
            <.mk_input
              field={@form[:name]}
              type="text"
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

            <fieldset class="pt-2">
              <legend class="text-sm font-semibold text-hero-black">
                {gettext("I want to...")}
              </legend>
              <p class="mt-1 text-sm text-[var(--fg-muted)]">
                {gettext("Select one or both options")}
              </p>
              <div class="mt-3 space-y-3">
                <label class="flex items-start gap-3 cursor-pointer rounded-xl border border-[var(--border-light)] p-3 hover:border-[var(--brand-primary)] transition-colors">
                  <input
                    type="checkbox"
                    name="user[intended_roles][]"
                    value="parent"
                    checked={:parent in (@form[:intended_roles].value || [])}
                    class="mt-1 rounded border-2 border-[var(--border-medium)] text-[var(--brand-primary)] focus:ring-2 focus:ring-[var(--focus-ring)]"
                  />
                  <div>
                    <span class="font-semibold text-hero-black">
                      {gettext("Enroll children in programs")}
                    </span>
                    <p class="text-sm text-[var(--fg-muted)]">
                      {gettext("Find and book activities, camps, and classes for your children")}
                    </p>
                  </div>
                </label>
                <label class="flex items-start gap-3 cursor-pointer rounded-xl border border-[var(--border-light)] p-3 hover:border-[var(--brand-primary)] transition-colors">
                  <input
                    type="checkbox"
                    name="user[intended_roles][]"
                    value="provider"
                    checked={:provider in (@form[:intended_roles].value || [])}
                    class="mt-1 rounded border-2 border-[var(--border-medium)] text-[var(--brand-primary)] focus:ring-2 focus:ring-[var(--focus-ring)]"
                  />
                  <div>
                    <span class="font-semibold text-hero-black">
                      {gettext("Offer programs and services")}
                    </span>
                    <p class="text-sm text-[var(--fg-muted)]">
                      {gettext("Create and manage programs, activities, and services for families")}
                    </p>
                  </div>
                </label>
              </div>
              <p
                :for={msg <- Enum.map(@form[:intended_roles].errors, &translate_error/1)}
                class="mt-2 text-sm text-[var(--error)]"
              >
                {msg}
              </p>
            </fieldset>

            <.kh_button
              type="submit"
              variant={:primary}
              size={:lg}
              class="w-full justify-center"
              phx-disable-with={gettext("Creating account...")}
            >
              {gettext("Create an account")}
            </.kh_button>
          </.form>
        </.kh_card>
      </div>
    </section>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket) when not is_nil(user) do
    {:ok, redirect(socket, to: KlassHeroWeb.UserAuth.signed_in_path(user))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{}, %{}, validate_unique: false)

    {:ok,
     socket
     |> assign(:active_nav, :auth)
     |> assign_form(changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("An email was sent to %{email}, please access it to confirm your account.",
             email: user.email
           )
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params, validate_unique: false)

    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
