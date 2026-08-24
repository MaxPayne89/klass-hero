defmodule KlassHeroWeb.UserLive.Login do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.MarketingComponents

  alias KlassHero.Accounts
  alias Swoosh.Adapters.Local

  @impl true
  def render(assigns) do
    ~H"""
    <.mk_page_hero pill={gettext("Sign in")}>
      <:title>
        {gettext("Welcome")}
        <span class="bg-hero-yellow-500 px-2 rounded-lg">{gettext("back")}</span>
      </:title>
      <:lede>
        <%= if @current_scope do %>
          {gettext("You need to reauthenticate to perform sensitive actions on your account.")}
        <% else %>
          {gettext("Sign in to continue. Don't have an account?")}
          <.link
            navigate={~p"/users/register"}
            class="font-bold text-[var(--fg-link)] hover:underline"
          >
            {gettext("Register")}
          </.link>
        <% end %>
      </:lede>
    </.mk_page_hero>

    <section class="relative pb-20 -mt-8 lg:-mt-12 px-6">
      <div class="max-w-md mx-auto">
        <.kh_card class="p-7 lg:p-9">
          <div :if={local_mail_adapter?()} class="alert alert-info mb-6">
            <.icon name="hero-information-circle" class="size-6 shrink-0" />
            <div>
              <p>{gettext("You are running the local mail adapter.")}</p>
              <p>
                {gettext("To see sent emails, visit")}
                <.link href="/dev/mailbox" class="underline">
                  {gettext("the mailbox page")}
                </.link>
              </p>
            </div>
          </div>

          <%= if !@show_password_form do %>
            <.form
              :let={f}
              for={@form}
              id="login_form_magic"
              action={~p"/users/log-in"}
              phx-submit="submit_magic"
              class="space-y-4"
            >
              <.mk_input
                field={f[:email]}
                type="email"
                label={gettext("Email")}
                placeholder="you@example.com"
                required
              />
              <.kh_button type="submit" variant={:primary} size={:lg} class="w-full justify-center">
                {gettext("Send magic link")}
              </.kh_button>
            </.form>

            <button
              type="button"
              phx-click="toggle_form"
              class="mt-4 w-full text-center text-sm font-semibold text-[var(--fg-muted)] hover:text-hero-black transition-colors"
            >
              {gettext("Or use password")}
            </button>
          <% else %>
            <.form
              :let={f}
              for={@form}
              id="login_form_password"
              action={~p"/users/log-in"}
              phx-submit="submit_password"
              phx-trigger-action={@trigger_submit}
              class="space-y-4"
            >
              <.mk_input
                field={f[:email]}
                type="email"
                label={gettext("Email")}
                placeholder="you@example.com"
                required
              />
              <.mk_input
                field={f[:password]}
                type="password"
                label={gettext("Password")}
                required
              />
              <div class="space-y-2 pt-2">
                <button
                  type="submit"
                  name={@form[:remember_me].name}
                  value="true"
                  class={
                    [
                      "inline-flex items-center justify-center gap-2 w-full px-7 py-3.5 text-lg rounded-xl",
                      # typography-lint-ignore: marketing form CTA mirrors KhButton primary surface
                      "font-display font-bold tracking-tight",
                      "bg-[var(--brand-primary)] hover:bg-[var(--brand-primary-hover)] text-black hover:shadow-lg hover:-translate-y-px transition-all cursor-pointer"
                    ]
                  }
                >
                  {gettext("Log in and stay logged in")} <span aria-hidden="true">→</span>
                </button>
                <.kh_button type="submit" variant={:ghost} size={:lg} class="w-full justify-center">
                  {gettext("Log in only this time")}
                </.kh_button>
              </div>
            </.form>

            <button
              type="button"
              phx-click="toggle_form"
              class="mt-4 w-full text-center text-sm font-semibold text-[var(--fg-muted)] hover:text-hero-black transition-colors"
            >
              {gettext("Or use magic link")}
            </button>
          <% end %>
        </.kh_card>
      </div>
    </section>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok,
     assign(socket,
       form: form,
       trigger_submit: false,
       show_password_form: true,
       active_nav: :auth
     )}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("toggle_form", _params, socket) do
    {:noreply, assign(socket, :show_password_form, !socket.assigns.show_password_form)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      gettext("If your email is in our system, you will receive instructions for logging in shortly.")

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:klass_hero, KlassHero.Mailer)[:adapter] == Local
  end
end
