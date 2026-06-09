defmodule KlassHero.Accounts.Application.Commands.LinkStaffInvitation do
  @moduledoc """
  Use case for linking an existing User to a staff invitation (#967, ADR-0005).

  Orchestrates the two-context write the one-click accept flow needs:
  the StaffMember link lives in Provider, the `:staff` role lives in Accounts.
  Accounts may depend on Provider (but not vice versa), so this orchestration
  belongs here — the LiveView calls a single function and never coordinates two
  contexts itself.

  Order is deliberate: verify the session email matches the invite, link the
  StaffMember, then append `:staff`. The role is granted only after a confirmed
  link, so a failure never leaves a user holding `:staff` without a staff row
  (privilege-safe). Both writes complete synchronously before the caller
  redirects, so `Scope.resolve_roles` sees the role and the link on the next mount.
  """

  alias KlassHero.Accounts.User
  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.Models.StaffMember

  @user_repository Application.compile_env!(:klass_hero, [:accounts, :for_storing_users])

  @doc """
  Links `user` to `staff_member` and grants `:staff`.

  The `user` must come from the authenticated session — never from params.
  Returns `{:error, :email_mismatch}` (no writes) unless the user's email
  matches the invite.
  """
  @spec execute(User.t(), StaffMember.t()) ::
          {:ok, User.t()} | {:error, :email_mismatch | term()}
  def execute(%User{} = user, %StaffMember{} = staff_member) do
    with :ok <- ensure_email_match(user, staff_member),
         {:ok, _linked} <- Provider.accept_staff_invitation(staff_member, user.id) do
      @user_repository.append_intended_role(user, :staff)
    end
  end

  defp ensure_email_match(%User{email: user_email}, %StaffMember{email: invite_email}) do
    if normalize(user_email) == normalize(invite_email),
      do: :ok,
      else: {:error, :email_mismatch}
  end

  defp normalize(nil), do: nil
  defp normalize(email) when is_binary(email), do: email |> String.trim() |> String.downcase()
end
