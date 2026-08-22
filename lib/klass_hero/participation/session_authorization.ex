defmodule KlassHero.Participation.SessionAuthorization do
  @moduledoc """
  What standing a `Scope` has on a `ProgramSession`.

  Two questions are asked of this module, and they differ only in how much of the
  answer they need:

  - **`authorize/2`** — who may write a child's attendance record. Every refusal is
    `:unauthorized`; no attendance caller has ever needed to tell them apart.
  - **`authorize_lifecycle/2`** — who may start or complete a Session. A refusal keeps
    its reason, because the staff sessions list says "This program has closed" rather
    than "Unauthorized", and that copy is the only thing this distinction buys (#1373).

  Both are thin over one private `resolve/2`. Neither contains rule-shaped code, which
  is the point: ADR-0019 argues that a rule respelled at each of N surfaces is a rule
  one surface eventually omits (#1323), and two authorizers that each re-derived "who
  are you here" would be exactly that shape.

  Attendance writes used to be guarded only by the web layer — and not even by a
  check there, but by the fact that `ParticipationLiveHandlers` looked records up
  in an assign an authorized query had populated at mount. The guard was emergent
  from the load path and stated nowhere, so any caller reaching the context
  directly had none (#1353). Session lifecycle writes were in the same state until
  #1373: `complete_session/1` took a bare id, and completing a Session marks every
  remaining `registered` child `absent`.

  ## Fall-through order

  A person is one User and may hold several personas at once, so "which rule
  applies" needs a deterministic answer. The order is **provider → staff →
  admin**: narrow to broad, first match wins, mirroring the precedence
  `KlassHeroWeb.Persona` already uses.

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

  ## A Closed Program refuses staff, and only staff (#1082)

  Once a program has been over for longer than the access grace window, its staff
  lose it. The refusal itself is not spelled out below: it arrives inside
  `SessionStaffing.staffed_by?/2`, which answers `false` for a closed program's
  session however genuinely staffed the caller is. That is deliberate, and it is why
  the *provider* and *admin* branches need no mention of closure — the provider owns
  the roster and still corrects it after the season, and an admin correction still
  demands its reason.

  What `refused_for_closure?/2` adds is not the rule but the *reason*, and it is
  narrower than the rule on purpose. `get_session_staffing/1` answers for any session
  id at all, so a reason read off `program_closed?` alone would tell any staff-persona
  caller the closure state of a program they had merely guessed an id for. Membership
  is still readable on a closed program — ADR-0019 gated only `staffed_by?/2` and
  `led_by?/2`, leaving `member_ids` alone so the provider's staffing panel keeps
  working — so the reason can say the true thing: *you would have been staff, but the
  program closed*. A stranger falls through to a bare `:unauthorized` and learns
  nothing.

  Closure is also asked **after** the admin branch, not before it. It is a staff rule,
  and asking it earlier would take the broader persona away from someone who happens
  to hold both.

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
  alias KlassHero.Provider.ReadModels.SessionStaffing

  @type role :: :provider | :staff | :admin
  @type refusal :: :unauthorized | :program_closed

  @doc """
  Resolves the scope's role for `session`, or refuses.

  Every refusal collapses to `:unauthorized`. Callers that need to tell a Closed
  Program apart from a program you were never on want `authorize_lifecycle/2`.

  Takes the session rather than its program id because the staff rule is answered
  at session grain; ownership and the admin flag are still program-wide facts, so
  those two branches read `session.program_id`.
  """
  @spec authorize(Scope.t(), ProgramSession.t()) :: {:ok, role()} | {:error, :unauthorized}
  def authorize(%Scope{} = scope, %ProgramSession{} = session) do
    case resolve(scope, session) do
      {:ok, role} -> {:ok, role}
      {:error, _reason} -> {:error, :unauthorized}
    end
  end

  @doc """
  Resolves the scope's role for `session`, or refuses **with the reason**.

  Same question as `authorize/2`, same answer, one more fact: a staff member who
  would have been authorized but for the program's closure gets `:program_closed`
  rather than `:unauthorized`, so the surface can say which it was.
  """
  @spec authorize_lifecycle(Scope.t(), ProgramSession.t()) :: {:ok, role()} | {:error, refusal()}
  def authorize_lifecycle(%Scope{} = scope, %ProgramSession{} = session), do: resolve(scope, session)

  # The one place a scope's standing on a session is decided.
  defp resolve(%Scope{} = scope, %ProgramSession{} = session) do
    cond do
      provider_owns?(scope, session.program_id) -> {:ok, :provider}
      is_nil(scope.staff_member) -> admin_or_refuse(scope)
      true -> resolve_staff(scope, session)
    end
  end

  # Reached only when the scope holds a staff persona, so the staffing read that
  # both the grant and the reason come from is never paid by a caller who cannot
  # use it.
  defp resolve_staff(%Scope{staff_member: staff_member} = scope, session) do
    staffing = Provider.get_session_staffing(session.id)

    cond do
      SessionStaffing.staffed_by?(staffing, staff_member.id) -> {:ok, :staff}
      admin?(scope) -> {:ok, :admin}
      refused_for_closure?(staff_member, staffing) -> {:error, :program_closed}
      true -> {:error, :unauthorized}
    end
  end

  defp admin_or_refuse(%Scope{} = scope) do
    if admin?(scope), do: {:ok, :admin}, else: {:error, :unauthorized}
  end

  defp provider_owns?(%Scope{provider: nil}, _program_id), do: false

  defp provider_owns?(%Scope{provider: provider}, program_id) do
    ProgramProviderResolver.resolve_provider_id(program_id) == {:ok, provider.id}
  end

  defp refused_for_closure?(staff_member, %SessionStaffing{program_closed?: true} = staffing),
    do: staff_member.id in staffing.member_ids

  defp refused_for_closure?(_staff_member, _staffing), do: false

  defp admin?(%Scope{user: %{is_admin: true}}), do: true
  defp admin?(%Scope{}), do: false
end
