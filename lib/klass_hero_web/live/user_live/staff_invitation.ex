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
            {gettext("This invitation has expired. Please ask your business to resend it.")}
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
              <.form
                for={@form}
                id="staff-registration-form"
                phx-submit="save"
                phx-change="validate"
                class="space-y-4"
              >
                <.mk_input
                  field={@form[:name]}
                  type="text"
                  label={gettext("Name")}
                  required
                />
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
        {:ok, assign(socket, error: :expired, form: nil, staff_member: nil)}
      else
        mount_registration_form(socket, staff_member)
      end
    else
      :error ->
        Logger.info("[StaffInvitation] Invalid base64 token")
        {:ok, assign(socket, error: :invalid, form: nil, staff_member: nil)}

      {:error, :not_found} ->
        Logger.info("[StaffInvitation] Token not found or already used")
        {:ok, assign(socket, error: :invalid, form: nil, staff_member: nil)}

      {:error, reason} ->
        Logger.error("[StaffInvitation] Unexpected error during token verification",
          reason: inspect(reason)
        )

        {:ok, assign(socket, error: :invalid, form: nil, staff_member: nil)}
    end
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    staff = socket.assigns.staff_member
    params = Map.put(user_params, "email", staff.email)

    case Accounts.register_staff_user(params) do
      {:ok, user} ->
        # Trigger: emit_staff_user_registered may fail (PubSub/Oban enqueue)
        # Why: the user account IS created; the critical event infrastructure
        #   guarantees eventual delivery via Oban durable retry
        # Outcome: proceed with success UX; the staff linkage self-heals
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
  def handle_event("validate", %{"user" => user_params}, socket) do
    staff = socket.assigns.staff_member
    params = Map.put(user_params, "email", staff.email)

    changeset =
      Accounts.change_staff_registration(params, validate_unique: false)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
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

  defp mount_registration_form(socket, staff_member) do
    changeset =
      Accounts.change_staff_registration(
        %{
          "name" => Provider.staff_member_full_name(staff_member),
          "email" => staff_member.email
        },
        validate_unique: false
      )

    {:ok,
     socket
     |> assign(
       staff_member: staff_member,
       error: nil,
       page_title: gettext("Complete Registration")
     )
     |> assign_form(changeset), temporary_assigns: [form: nil]}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
