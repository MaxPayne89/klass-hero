defmodule KlassHero.Participation.AttendanceAuthorization do
  @moduledoc """
  Who may write a child's attendance record.

  Attendance writes used to be guarded only by the web layer — and not even by a
  check there, but by the fact that `ParticipationLiveHandlers` looked records up
  in an assign an authorized query had populated at mount. The guard was emergent
  from the load path and stated nowhere, so any caller reaching the context
  directly had none (#1353). This module is that check, at the boundary where the
  write happens.

  ## Fall-through order

  A person is one User and may hold several personas at once, so "which rule
  applies" needs a deterministic answer. The order is **provider → staff →
  admin**: narrow to broad, first match wins, mirroring the precedence
  `KlassHeroWeb.RoleRouting.primary_role/1` already uses.

  The order is load-bearing, not alphabetical. An admin who also owns a provider
  gets *provider* rules on their own programs — correct, they are the provider,
  and `correct_attendance` therefore does not demand a correction reason from
  them. They fall through to *admin* only on programs they do not own, where a
  reason is demanded. Admin-first would invert that and force a reason on a
  provider editing their own roster.

  A staff member with no assignment is authorized for nothing, per
  `StaffProgramAccess`'s own rule (#1323): assignment is a deliberate act, so
  "not assigned yet" and "not allowed" are the same fact.
  """

  alias KlassHero.Accounts.Scope
  alias KlassHero.Participation.Adapters.Driven.ACL.ProgramProviderResolver
  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.ReadModels.StaffProgramAccess

  @type role :: :provider | :staff | :admin

  @doc """
  Resolves the scope's role for `program_id`, or refuses.
  """
  @spec authorize(Scope.t(), String.t()) :: {:ok, role()} | {:error, :unauthorized}
  def authorize(%Scope{} = scope, program_id) when is_binary(program_id) do
    cond do
      provider_owns?(scope, program_id) -> {:ok, :provider}
      staff_assigned?(scope, program_id) -> {:ok, :staff}
      admin?(scope) -> {:ok, :admin}
      true -> {:error, :unauthorized}
    end
  end

  defp provider_owns?(%Scope{provider: nil}, _program_id), do: false

  defp provider_owns?(%Scope{provider: provider}, program_id) do
    ProgramProviderResolver.resolve_provider_id(program_id) == {:ok, provider.id}
  end

  defp staff_assigned?(%Scope{staff_member: nil}, _program_id), do: false

  defp staff_assigned?(%Scope{staff_member: staff_member}, program_id) do
    staff_member.id
    |> Provider.get_staff_program_access()
    |> StaffProgramAccess.authorized?(program_id)
  end

  defp admin?(%Scope{user: %{is_admin: true}}), do: true
  defp admin?(%Scope{}), do: false
end
