defmodule KlassHeroWeb.InviteClaimController do
  @moduledoc """
  Handles GET /invites/:token — the public endpoint a guardian clicks
  from their invite email.

  Delegates to `Enrollment.claim_invite/1` which either creates a new
  user or finds an existing one, then redirects accordingly.
  """

  use KlassHeroWeb, :controller

  alias KlassHero.Accounts
  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.Application.ClaimResult

  require Logger

  def show(conn, %{"token" => token}) do
    case Enrollment.claim_invite(token) do
      {:ok, %ClaimResult{user_type: :new_user, user: user}} ->
        # No password yet — magic-link lets them in immediately.
        # ClaimInvite returns a lightweight map; re-fetch full %User{} for Accounts API.
        full_user = Accounts.get_user!(user.id)
        magic_token = Accounts.generate_magic_link_token(full_user)

        conn
        |> put_flash(
          :info,
          gettext("Your account has been created! Set up your password in settings.")
        )
        |> redirect(to: ~p"/users/log-in/#{magic_token}")

      {:ok, %ClaimResult{user_type: :existing_user}} ->
        conn
        |> put_flash(
          :info,
          gettext("You already have an account. Log in to see your new enrollment.")
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, :not_found} ->
        Logger.warning("[InviteClaimController] Invalid or expired invite token attempted")

        conn
        |> put_flash(:error, gettext("This invite link is invalid or has expired."))
        |> redirect(to: ~p"/")

      {:error, :already_claimed} ->
        conn
        |> put_flash(:info, gettext("This invite has already been used."))
        |> redirect(to: ~p"/users/log-in")
    end
  end
end
