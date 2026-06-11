defmodule KlassHero.Accounts.Application.Commands.LinkStaffInvitation do
  @moduledoc """
  Use case for linking an existing User to a staff invitation (#967, ADR-0005).

  Orchestrates the two-context write the one-click accept flow needs:
  the StaffMember link lives in Provider, the `:staff` role lives in Accounts.
  Accounts may depend on Provider (but not vice versa), so this orchestration
  belongs here — the LiveView calls a single function and never coordinates two
  contexts itself.

  Order is deliberate: verify the session email matches the invite, link the
  StaffMember, then append `:staff`. Both writes run in one DB transaction (same
  Repo, different contexts), so a failure in either rolls back both — never an
  `:accepted` staff row whose user lacks `:staff`, nor a `:staff` role without a
  link. Both complete synchronously before the caller redirects, so
  `Scope.resolve_roles` sees the role and the link on the next mount.
  """

  alias KlassHero.Accounts
  alias KlassHero.Accounts.Application.Commands.PersonaGrant
  alias KlassHero.Accounts.User
  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.Models.StaffMember

  @doc """
  Links `user` to `staff_member` and grants `:staff`, atomically.

  The `user` must come from the authenticated session — never from params.
  Returns `{:error, :email_mismatch}` (no writes) unless the user's email
  matches the invite.
  """
  @spec execute(User.t(), StaffMember.t()) ::
          {:ok, User.t()} | {:error, :email_mismatch | term()}
  def execute(%User{} = user, %StaffMember{} = staff_member) do
    with :ok <- ensure_email_match(user, staff_member),
         {:ok, {updated_user, _linked}} <-
           PersonaGrant.grant(user, :staff, fn fresh_user ->
             Provider.accept_staff_invitation(staff_member, fresh_user.id)
           end) do
      {:ok, updated_user}
    end
  end

  defp ensure_email_match(%User{email: user_email}, %StaffMember{email: invite_email}) do
    if Accounts.emails_match?(user_email, invite_email),
      do: :ok,
      else: {:error, :email_mismatch}
  end
end
