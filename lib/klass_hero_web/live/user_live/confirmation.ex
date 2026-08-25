defmodule KlassHeroWeb.UserLive.Confirmation do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.MarketingComponents

  alias KlassHero.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <.mk_page_hero pill={gettext("Confirm")}>
      <:title>
        {gettext("Welcome")}
        <span class="bg-hero-yellow-500 px-2 rounded-lg">{@user.email}</span>
      </:title>
      <:lede>
        <%= if @user.confirmed_at do %>
          {gettext("Click below to log in.")}
        <% else %>
          {gettext("Confirm your account to finish signing up.")}
        <% end %>
      </:lede>
    </.mk_page_hero>

    <section class="relative pb-20 -mt-8 lg:-mt-12 px-6">
      <div class="max-w-md mx-auto">
        <.kh_card class="p-7 lg:p-9">
          <.form
            :if={!@user.confirmed_at}
            for={@form}
            id="confirmation_form"
            phx-auto-recover="ignore"
            phx-mounted={JS.focus_first()}
            phx-submit="submit"
            action={~p"/users/log-in?_action=confirmed"}
            phx-trigger-action={@trigger_submit}
            class="space-y-3"
          >
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <.kh_button
              type="submit"
              variant={:primary}
              size={:lg}
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with={gettext("Confirming...")}
              class="w-full justify-center"
            >
              {gettext("Confirm and stay logged in")}
            </.kh_button>
            <.kh_button
              type="submit"
              variant={:ghost}
              size={:lg}
              phx-disable-with={gettext("Confirming...")}
              class="w-full justify-center"
            >
              {gettext("Confirm and log in only this time")}
            </.kh_button>
          </.form>

          <.form
            :if={@user.confirmed_at}
            for={@form}
            id="login_form"
            phx-auto-recover="ignore"
            phx-submit="submit"
            phx-mounted={JS.focus_first()}
            action={~p"/users/log-in"}
            phx-trigger-action={@trigger_submit}
            class="space-y-3"
          >
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <%= if @current_scope do %>
              <.kh_button
                type="submit"
                variant={:primary}
                size={:lg}
                phx-disable-with={gettext("Logging in...")}
                class="w-full justify-center"
              >
                {gettext("Log in")}
              </.kh_button>
            <% else %>
              <.kh_button
                type="submit"
                variant={:primary}
                size={:lg}
                name={@form[:remember_me].name}
                value="true"
                phx-disable-with={gettext("Logging in...")}
                class="w-full justify-center"
              >
                {gettext("Keep me logged in on this device")}
              </.kh_button>
              <.kh_button
                type="submit"
                variant={:ghost}
                size={:lg}
                phx-disable-with={gettext("Logging in...")}
                class="w-full justify-center"
              >
                {gettext("Log me in only this time")}
              </.kh_button>
            <% end %>
          </.form>

          <p
            :if={!@user.confirmed_at}
            class="mt-6 text-sm text-[var(--fg-muted)] border-l-4 border-hero-yellow-500 pl-4 leading-relaxed"
          >
            {gettext("Tip: If you prefer passwords, you can enable them in the user settings.")}
          </p>
        </.kh_card>
      </div>
    </section>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok,
       assign(socket,
         user: user,
         form: form,
         trigger_submit: false,
         active_nav: :auth
       ), temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Magic link is invalid or it has expired."))
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
