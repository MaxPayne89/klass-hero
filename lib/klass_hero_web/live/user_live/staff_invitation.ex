defmodule KlassHeroWeb.UserLive.StaffInvitation do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.MarketingComponents

  alias KlassHero.Accounts
  alias KlassHero.Provider

  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <%= cond do %>
      <% @error == :invalid -> %>
        <.mk_page_hero pill={gettext("Invitation")}>
          <:title>{gettext("Invalid Invitation")}</:title>
          <:lede>{gettext("This invitation link is invalid or has already been used.")}</:lede>
        </.mk_page_hero>
        <section class="relative pb-20 -mt-8 lg:-mt-12 px-6 text-center">
          <.link navigate={~p"/"}>
            <.kh_button variant={:primary} size={:lg}>{gettext("Go to Home")}</.kh_button>
          </.link>
        </section>
      <% @error == :expired -> %>
        <.mk_page_hero pill={gettext("Invitation")}>
          <:title>{gettext("Invitation Expired")}</:title>
          <:lede>
            {gettext("This invitation has expired. Please ask your provider to resend it.")}
          </:lede>
        </.mk_page_hero>
        <section class="relative pb-20 -mt-8 lg:-mt-12 px-6 text-center">
          <.link navigate={~p"/"}>
            <.kh_button variant={:primary} size={:lg}>{gettext("Go to Home")}</.kh_button>
          </.link>
        </section>
      <% true -> %>
        <.mk_page_hero pill={gettext("Join the team")}>
          <:title>
            {gettext("Join the")}
            <span class="bg-hero-yellow-500 px-2 rounded-lg">{gettext("team")}</span>
          </:title>
          <:lede>{gettext("You've been invited to join a team on Klass Hero.")}</:lede>
        </.mk_page_hero>

        <section class="relative pb-20 -mt-8 lg:-mt-12 px-6">
          <div class="max-w-md mx-auto">
            <.kh_card class="p-7 lg:p-9">
              <%= case @mode do %>
                <% :loading -> %>
                  <div id="staff-invite-loading" class="space-y-3 text-center text-hero-grey-600">
                    <p>{gettext("Loading your invitation…")}</p>
                  </div>
                <% :register -> %>
                  <.form
                    for={@form}
                    id="staff-registration-form"
                    phx-submit="save"
                    phx-change="validate"
                    class="space-y-4"
                  >
                    <.mk_input field={@form[:name]} type="text" label={gettext("Name")} required />
                    <.mk_input
                      field={@form[:email]}
                      type="email"
                      label={gettext("Email")}
                      required
                      readonly
                    />
                    <.mk_input
                      field={@form[:password]}
                      type="password"
                      label={gettext("Password")}
                      required
                    />
                    <.kh_button
                      type="submit"
                      variant={:primary}
                      size={:lg}
                      class="w-full justify-center"
                      phx-disable-with={gettext("Creating account...")}
                    >
                      {gettext("Complete Registration")}
                    </.kh_button>
                  </.form>
                <% :must_log_in -> %>
                  <div id="staff-invite-login-prompt" class="space-y-5 text-center">
                    <p class="text-hero-black-100">
                      {gettext("You already have an account for %{email}.", email: @invite_email)}
                    </p>
                    <p class="text-hero-grey-600 text-sm">
                      {gettext("Log in, then reopen this invitation to join the team.")}
                    </p>
                    <.link navigate={~p"/users/log-in"}>
                      <.kh_button variant={:primary} size={:lg} class="w-full justify-center">
                        {gettext("Log in")}
                      </.kh_button>
                    </.link>
                  </div>
                <% :link -> %>
                  <div id="staff-invite-link" class="space-y-5 text-center">
                    <p class="text-hero-black-100">
                      {gettext("Link this invitation to your account %{email}.", email: @invite_email)}
                    </p>
                    <.kh_button
                      id="staff-invite-link-button"
                      variant={:primary}
                      size={:lg}
                      class="w-full justify-center"
                      phx-click="link"
                      phx-disable-with={gettext("Linking...")}
                    >
                      {gettext("Link my account")}
                    </.kh_button>
                  </div>
                <% :wrong_account -> %>
                  <div id="staff-invite-wrong-account" class="space-y-5 text-center">
                    <p class="text-hero-black-100">
                      {gettext("This invitation is for %{invite}.", invite: @invite_email)}
                    </p>
                    <p class="text-hero-grey-600 text-sm">
                      {gettext(
                        "You're logged in as %{current}. Log into the matching account to accept.",
                        current: @current_scope.user.email
                      )}
                    </p>
                    <.link href={~p"/users/log-out"} method="delete">
                      <.kh_button variant={:secondary} size={:lg} class="w-full justify-center">
                        {gettext("Log out")}
                      </.kh_button>
                    </.link>
                  </div>
              <% end %>
            </.kh_card>
          </div>
        </section>
    <% end %>
    """
  end

  @impl true
  def mount(%{"token" => raw_token}, _session, socket) do
    with {:ok, decoded} <- Base.url_decode64(raw_token, padding: false),
         token_hash = :crypto.hash(:sha256, decoded),
         {:ok, staff_member} <- Provider.get_staff_member_by_token_hash(token_hash) do
      if Provider.invitation_expired?(staff_member) do
        maybe_persist_expiry(socket, staff_member)
        {:ok, assign_error(socket, :expired)}
      else
        mount_for_mode(socket, staff_member)
      end
    else
      :error ->
        Logger.info("[StaffInvitation] Invalid base64 token")
        {:ok, assign_error(socket, :invalid)}

      {:error, :not_found} ->
        Logger.info("[StaffInvitation] Token not found or already used")
        {:ok, assign_error(socket, :invalid)}
    end
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    staff = socket.assigns.staff_member
    params = Map.put(user_params, "email", staff.email)

    case Accounts.register_staff_user(params) do
      {:ok, user} ->
        # User is created; Oban guarantees eventual delivery of the event even if this enqueue fails.
        case Accounts.emit_staff_user_registered(user.id, staff.id, staff.provider_id) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error("[StaffInvitation] Failed to emit staff_user_registered",
              user_id: user.id,
              staff_member_id: staff.id,
              reason: inspect(reason)
            )
        end

        case Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}")) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error("[StaffInvitation] Failed to deliver login instructions",
              user_id: user.id,
              reason: inspect(reason)
            )
        end

        {:noreply,
         socket
         |> put_flash(:info, gettext("Account created! Check your email to confirm and log in."))
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def handle_event("link", _params, %{assigns: %{mode: :link}} = socket) do
    user = current_user(socket)
    staff = socket.assigns.staff_member

    case Accounts.link_staff_invitation(user, staff) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("You're now part of the team."))
         |> push_navigate(to: ~p"/staff/dashboard")}

      {:error, :email_mismatch} ->
        # Defense: a forged click from a non-matching session cannot link.
        {:noreply, assign(socket, mode: :wrong_account)}

      {:error, reason} ->
        Logger.error("[StaffInvitation] Failed to link staff invitation",
          staff_member_id: staff.id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Could not link your account. Please try again."))}
    end
  end

  # Ignore "link" events in any mode other than :link (e.g. crafted client events).
  def handle_event("link", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    staff = socket.assigns.staff_member
    params = Map.put(user_params, "email", staff.email)

    changeset =
      Accounts.change_staff_registration(params, validate_unique: false)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  defp assign_error(socket, error) do
    assign(socket,
      error: error,
      mode: nil,
      form: nil,
      staff_member: nil,
      invite_email: nil
    )
  end

  defp mount_for_mode(socket, staff_member) do
    # Defer the email lookup to connected mount so the token endpoint isn't double-queried.
    mode =
      if connected?(socket),
        do: resolve_mode(current_user(socket), staff_member.email),
        else: :loading

    socket =
      assign(socket,
        staff_member: staff_member,
        error: nil,
        mode: mode,
        invite_email: staff_member.email,
        page_title: gettext("Join the team")
      )

    {:ok, maybe_assign_register_form(socket, mode, staff_member)}
  end

  # Mode derives from session truth only, never params — the :link button only renders on email match.
  defp resolve_mode(nil = _current_user, invite_email) do
    if Accounts.get_user_by_email(invite_email), do: :must_log_in, else: :register
  end

  defp resolve_mode(current_user, invite_email) do
    if Accounts.emails_match?(current_user.email, invite_email), do: :link, else: :wrong_account
  end

  defp maybe_assign_register_form(socket, :register, staff_member) do
    changeset =
      Accounts.change_staff_registration(
        %{
          "name" => Provider.staff_member_full_name(staff_member),
          "email" => staff_member.email
        },
        validate_unique: false
      )

    assign_form(socket, changeset)
  end

  defp maybe_assign_register_form(socket, _mode, _staff_member), do: assign(socket, form: nil)

  defp current_user(socket) do
    case socket.assigns[:current_scope] do
      %{user: %{} = user} -> user
      _ -> nil
    end
  end

  defp maybe_persist_expiry(socket, staff_member) do
    if connected?(socket) do
      case Provider.expire_staff_invitation(staff_member) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("[StaffInvitation] Failed to expire invitation",
            staff_member_id: staff_member.id,
            reason: inspect(reason)
          )
      end
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
