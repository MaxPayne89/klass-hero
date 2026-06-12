defmodule KlassHero.Accounts.Application.Commands.RemoveStaffMember do
  @moduledoc """
  Deletes a staff member row and tears down the now-backing-less `:staff` role
  (ADR-0005, #972) — the mirror of the persona-GRANT flows.

  Deletion lives in the Provider context, but `intended_roles` lives in Accounts
  and Boundary forbids Provider → Accounts, so the orchestration sits here (the
  same reason `UpgradeToProvider` does a Provider write from Accounts). Both
  writes run in ONE `Repo.transaction` so there's never a window where the row is
  gone but the role lingers, or vice versa.

  `:staff` is removed ONLY when the deleted row was LINKED (`user_id` set) and no
  other active linked row remains for that user at any provider — multi-employer
  users keep the role. Unlinked display-only rows never touch roles.
  """

  alias KlassHero.Accounts.User
  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.Models.StaffMember
  alias KlassHero.Repo

  @user_repository Application.compile_env!(:klass_hero, [:accounts, :for_storing_users])

  @doc """
  Deletes the staff row `staff_id`, conditionally revoking `:staff`.

  Returns `{:ok, deleted_staff}` or `{:error, :not_found}`.
  """
  @spec execute(String.t()) :: {:ok, StaffMember.t()} | {:error, :not_found}
  def execute(staff_id) when is_binary(staff_id) do
    Repo.transaction(fn ->
      with {:ok, staff} <- Provider.get_staff_member(staff_id),
           :ok <- Provider.delete_staff_member(staff_id),
           :ok <- maybe_revoke_staff_role(staff) do
        staff
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # Unlinked display-only row — no persona to tear down.
  defp maybe_revoke_staff_role(%StaffMember{user_id: nil}), do: :ok

  defp maybe_revoke_staff_role(%StaffMember{user_id: user_id}) do
    # Queried AFTER the delete (same transaction), so the just-removed row is
    # already gone: :not_found means this was the user's last active employment.
    case Provider.get_active_staff_member_by_user(user_id) do
      {:ok, _still_employed} -> :ok
      {:error, :not_found} -> revoke_staff(user_id)
    end
  end

  defp revoke_staff(user_id) do
    case Repo.get(User, user_id) do
      # Re-fetched inside the txn (lost-update guard, mirroring PersonaGrant).
      %User{} = user ->
        with {:ok, _updated} <- @user_repository.remove_intended_role(user, :staff), do: :ok

      nil ->
        :ok
    end
  end
end
