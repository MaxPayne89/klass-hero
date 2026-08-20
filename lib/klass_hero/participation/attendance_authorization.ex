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

  ## The staff rule is asked at session grain (#783)

  Since #782 a provider can staff one session differently from its program, so
  "assigned to the program" stopped being the whole answer. The staff branch asks
  `Provider.get_session_staffing/1`, which resolves a session's own overrides when
  it has any and falls back to the program roster when it does not — one question,
  with the program grain as its fallback rather than as a second rule beside it.

  That distinction is the point, and it is *not* what #783 originally specified.
  OR-ing a session check onto a program check reads as more permissive in the
  right direction only. It is also more permissive in the wrong one:
  `unassign_staff_from_session/3` takes someone off a single session by
  materializing the program roster and dropping them from it, and their
  `ProgramStaffAssignment` deliberately survives that. Under an OR they would
  still authorize — the removal silently undone at the layer that enforces it.
  """

  alias KlassHero.Accounts.Scope
  alias KlassHero.Participation.Adapters.Driven.ACL.ProgramProviderResolver
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.ReadModels.SessionStaffing

  @type role :: :provider | :staff | :admin

  @doc """
  Resolves the scope's role for `session`, or refuses.

  Takes the session rather than its program id because the staff rule is answered
  at session grain; ownership and the admin flag are still program-wide facts, so
  those two branches read `session.program_id`.
  """
  @spec authorize(Scope.t(), ProgramSession.t()) :: {:ok, role()} | {:error, :unauthorized}
  def authorize(%Scope{} = scope, %ProgramSession{} = session) do
    cond do
      provider_owns?(scope, session.program_id) -> {:ok, :provider}
      staff_on_session?(scope, session) -> {:ok, :staff}
      admin?(scope) -> {:ok, :admin}
      true -> {:error, :unauthorized}
    end
  end

  defp provider_owns?(%Scope{provider: nil}, _program_id), do: false

  defp provider_owns?(%Scope{provider: provider}, program_id) do
    ProgramProviderResolver.resolve_provider_id(program_id) == {:ok, provider.id}
  end

  defp staff_on_session?(%Scope{staff_member: nil}, _session), do: false

  defp staff_on_session?(%Scope{staff_member: staff_member}, session) do
    session.id
    |> Provider.get_session_staffing()
    |> SessionStaffing.staffed_by?(staff_member.id)
  end

  defp admin?(%Scope{user: %{is_admin: true}}), do: true
  defp admin?(%Scope{}), do: false
end
