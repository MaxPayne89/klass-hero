defmodule KlassHero.Provider.Assignments do
  @moduledoc """
  Program ↔ staff assignment commands and queries for the Provider context.

  Assignment writes stage their events in the same transaction as the write; reads
  expose active assignments and the staff behind them. Reached through
  `KlassHero.Provider`'s public API.

  ## Tenancy

  Every write takes a `provider_id` and enforces it uniformly (#1134): the staff
  member comes from a scoped getter (see ## Employment below), the program from the
  scoped `ProgramCatalog.get_program_for_provider/2` (via `ensure_program_owned/2`), and
  every UPDATE is narrowed by `ProgramStaffAssignment.owned_by/2`. Ownership is a
  property of the queries, not a caller convention, so no UPDATE can reach a
  foreign row even if a pre-check were missed.

  INSERTs are the one shape a query scope can't cover, so they take their
  `provider_id` from the ownership-proven `StaffMember` rather than from caller
  attrs — see `build_assignment_attrs/2` and `upsert_lead/4`.

  Foreign and missing are deliberately indistinguishable throughout — both
  `{:error, :not_found}`, leaking no existence oracle.

  ## Employment

  Which scoped getter a write uses depends on whether it *creates* an attachment
  (#1306). `assign_staff_to_program/1` and `set_lead_instructor/3` take
  `Provider.get_active_staff_member/2`, so a deactivated member cannot be newly
  attached — the read side filters them out, and a write the reads then hide is a
  silent no-op with a real row behind it.

  `unassign_staff_from_program/3` uses the tenancy-only `Provider.get_staff_member/2`
  on purpose: deactivation leaves existing assignments alive, so detaching someone
  after they were offboarded has to stay possible.

  Deactivated collapses into the same `{:error, :not_found}` as foreign and missing,
  so this adds no third error branch for callers.

  Reads are intentionally *not* provider-scoped: `get_lead_instructor/1` and its
  batch sibling feed publicly-rendered program pages.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias KlassHero.Participation
  alias KlassHero.ProgramCatalog
  alias KlassHero.Provider
  alias KlassHero.Provider.Events
  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Provider.ReadModels.ProgramStaffing
  alias KlassHero.Provider.ReadModels.SessionStaffing
  alias KlassHero.Provider.ReadModels.StaffProgramAccess
  alias KlassHero.Provider.SessionStaffAssignment
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.Outbox

  require Logger

  @context KlassHero.Provider

  @doc """
  Assigns a staff member to a program.

  `attrs.provider_id` is the tenancy authority and must come from the
  authenticated scope, never from client input. Both the staff member and the
  program are verified to belong to it.

  Returns:
  - `{:ok, ProgramStaffAssignment.t()}` on success
  - `{:error, :already_assigned}` if the staff member is already assigned
  - `{:error, :not_found}` if the staff member or program is missing or foreign, or
    the staff member is deactivated (#1306 — deactivated ≡ foreign ≡ missing)
  """
  @spec assign_staff_to_program(map()) ::
          {:ok, ProgramStaffAssignment.t()}
          | {:error, :already_assigned | :not_found | term()}
  def assign_staff_to_program(%{provider_id: provider_id} = attrs) do
    context_span entity: "program_staff_assignment" do
      with {:ok, staff_member} <- Provider.get_active_staff_member(attrs.staff_member_id, provider_id),
           :ok <- ensure_program_owned(attrs.program_id, provider_id),
           assignment_attrs = build_assignment_attrs(attrs, staff_member),
           {:ok, assignment} <-
             assign_with_event(assignment_attrs, staff_member) do
        Logger.info("Staff member assigned to program",
          staff_member_id: assignment.staff_member_id,
          program_id: assignment.program_id
        )

        {:ok, assignment}
      end
    end
  end

  @doc """
  Unassigns a staff member from a program owned by `provider_id`.

  Refuses when the target is the program's lead instructor: detaching them would
  silently leave the program lead-less off a single click. Promote a replacement
  (`set_lead_instructor/3`) or step them down (`clear_lead_instructor/2`) first.

  That guard is deliberately **not** mirrored on
  `Provider.Staff.deactivate_staff_member/1`, which clears lead flags and leaves
  a lead-less program behind without complaint. The asymmetry is the point: a
  lead-less program is a sanctioned state (the program form produces one on every
  blanked select), so this is not an invariant — it is a rail on *this* command,
  the interactive detach of one row from one program. Deactivation is an
  employment-lifecycle cascade across every program, and offboarding or GDPR
  erasure must never block on someone not having picked a new camp lead yet.

  Returns:
  - `{:ok, ProgramStaffAssignment.t()}` on success
  - `{:error, :cannot_unassign_lead}` if the staff member currently leads the program
  - `{:error, :not_found}` if no active assignment exists or it is foreign
  """
  @spec unassign_staff_from_program(String.t(), String.t(), String.t()) ::
          {:ok, ProgramStaffAssignment.t()} | {:error, :not_found | :cannot_unassign_lead | term()}
  def unassign_staff_from_program(program_id, staff_member_id, provider_id)
      when is_binary(program_id) and is_binary(staff_member_id) and is_binary(provider_id) do
    context_span entity: "program_staff_assignment" do
      with {:ok, staff_member} <- Provider.get_staff_member(staff_member_id, provider_id),
           {:ok, assignment} <-
             unassign_with_event(program_id, staff_member_id, provider_id, staff_member) do
        Logger.info("Staff member unassigned from program",
          staff_member_id: staff_member_id,
          program_id: program_id
        )

        {:ok, assignment}
      end
    end
  end

  @doc """
  Adds a staff member to one session, giving that session a roster of its own.

  Additive. The first add to a session that still inherits copies the program's
  visible roster across first, so the result is "the usual team plus this person",
  not "this person instead of the usual team" — see `materialize_program_roster/2`
  for why that copy is still compatible with a sparse table.

  `attrs.provider_id` is the tenancy authority and must come from the
  authenticated scope. `attrs.assigned_by_user_id` is optional and records who
  made the override.

  Returns:
  - `{:ok, SessionStaffAssignment.t()}` on success
  - `{:error, :already_assigned}` if the staff member already overrides this session
  - `{:error, :not_found}` if the staff member or session is missing or foreign, or
    the staff member is deactivated (#1306 — deactivated ≡ foreign ≡ missing)
  """
  @spec assign_staff_to_session(map()) ::
          {:ok, SessionStaffAssignment.t()}
          | {:error, :already_assigned | :not_found | term()}
  def assign_staff_to_session(%{provider_id: provider_id} = attrs) do
    context_span entity: "session_staff_assignment" do
      with {:ok, staff_member} <- Provider.get_active_staff_member(attrs.staff_member_id, provider_id),
           {:ok, session} <- ensure_session_owned(attrs.session_id, provider_id),
           assignment_attrs = build_assignment_attrs(attrs, staff_member),
           {:ok, assignment} <- assign_to_session_with_event(assignment_attrs, staff_member, session) do
        Logger.info("Staff member assigned to session",
          staff_member_id: assignment.staff_member_id,
          session_id: assignment.session_id
        )

        {:ok, assignment}
      end
    end
  end

  @doc """
  Removes one staff member from a session owned by `provider_id`.

  Works on a session that still inherits: the program roster is materialized first,
  so removing one person leaves the rest rather than emptying the session.

  Refuses when the target leads the session, for the same reason the program-level
  sibling does: detaching them would leave the session lead-less off a single
  click. Promote a replacement or step them down first.

  Refuses to remove the *last* member. Zero override rows means "inherits the
  program roster", so emptying a session this way would snap it back to showing the
  whole team — `revert_session_to_program_roster/2` is the honest way to say that,
  and the only one.

  Returns:
  - `{:ok, SessionStaffAssignment.t()}` on success
  - `{:error, :cannot_unassign_lead}` if the staff member currently leads the session
  - `{:error, :cannot_empty_session}` if they are the session's only member
  - `{:error, :not_found}` if they are not on the session, or it is foreign
  """
  @spec unassign_staff_from_session(String.t(), String.t(), String.t()) ::
          {:ok, SessionStaffAssignment.t()}
          | {:error, :not_found | :cannot_unassign_lead | :cannot_empty_session | term()}
  def unassign_staff_from_session(session_id, staff_member_id, provider_id)
      when is_binary(session_id) and is_binary(staff_member_id) and is_binary(provider_id) do
    context_span entity: "session_staff_assignment" do
      with {:ok, staff_member} <- Provider.get_staff_member(staff_member_id, provider_id),
           {:ok, session} <- ensure_session_owned(session_id, provider_id),
           {:ok, assignment} <-
             unassign_from_session_with_event(session_id, staff_member_id, provider_id, staff_member, session) do
        Logger.info("Staff member unassigned from session",
          staff_member_id: staff_member_id,
          session_id: session_id
        )

        {:ok, assignment}
      end
    end
  end

  @doc """
  Retires every override on a session, returning it to the program roster.

  The bulk counterpart of `unassign_staff_from_session/3`, and not expressible as a
  loop over it: that command refuses to detach the session lead, which is right for
  an interactive one-row detach and wrong here. Reverting is a deliberate "this
  session has no staffing of its own", so the lead goes with the rest.

  Returns `{:ok, retired_count}` — zero when the session already inherits — or
  `{:error, :not_found}` when the session is missing or foreign.
  """
  @spec revert_session_to_program_roster(String.t(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, :not_found | term()}
  def revert_session_to_program_roster(session_id, provider_id) when is_binary(session_id) and is_binary(provider_id) do
    context_span entity: "session_staff_assignment" do
      with {:ok, session} <- ensure_session_owned(session_id, provider_id) do
        revert_session_with_events(session_id, provider_id, session)
      end
    end
  end

  @doc """
  Flags one of a session's members as its lead instructor.

  Promoting on a session that still inherits materializes the program roster first
  (see `materialize_program_roster/2`), so the session keeps everyone it was showing
  and gains its own lead. This used to refuse with `{:error, :not_found}` precisely
  because creating a lone override row would have silently discarded the rest of the
  roster; materialization removes that hazard, so the refusal protected nothing.

  Idempotent and transactional: the roster copy, clearing any previous session lead,
  and flagging the target all commit together, so the
  `session_staff_assignments_single_lead` partial unique index is never violated
  mid-flight.

  Returns `{:error, :not_found}` when the staff member or session is missing or
  foreign, the staff member is deactivated, or they are not on this session at all.
  """
  @spec set_session_lead_instructor(String.t(), String.t(), String.t()) ::
          {:ok, SessionStaffAssignment.t()} | {:error, :not_found | term()}
  def set_session_lead_instructor(session_id, staff_member_id, provider_id)
      when is_binary(session_id) and is_binary(staff_member_id) and is_binary(provider_id) do
    context_span entity: "session_staff_assignment" do
      with {:ok, staff_member} <- Provider.get_active_staff_member(staff_member_id, provider_id),
           {:ok, session} <- ensure_session_owned(session_id, provider_id) do
        Multi.new()
        # Ahead of :clear_other_leads on purpose — a materialized program lead has to
        # exist before the query that steps them down can see them.
        |> Multi.run(:materialize, fn _repo, _changes ->
          :ok = materialize_program_roster(session, provider_id)
          {:ok, :materialized}
        end)
        |> Multi.update_all(
          :clear_other_leads,
          other_active_session_leads_query(session_id, staff_member.id, provider_id),
          set: [is_lead_instructor: false]
        )
        |> Multi.run(:lead, fn repo, _ -> promote_session_lead(repo, session_id, staff_member.id, provider_id) end)
        |> Repo.transaction()
        |> case do
          {:ok, %{lead: lead}} -> {:ok, lead}
          {:error, _step, reason, _changes} -> {:error, reason}
        end
      end
    end
  end

  @doc """
  Clears the session's lead instructor, leaving the override otherwise active.

  No-op when the session has no lead or is foreign.
  """
  @spec clear_session_lead_instructor(String.t(), String.t()) :: :ok
  def clear_session_lead_instructor(session_id, provider_id) when is_binary(session_id) and is_binary(provider_id) do
    from(a in SessionStaffAssignment.owned_by(provider_id),
      where: a.session_id == ^session_id and a.is_lead_instructor and is_nil(a.unassigned_at)
    )
    |> Repo.update_all(set: [is_lead_instructor: false])

    :ok
  end

  @doc """
  Who is on one session: its overrides when it has any, otherwise the program roster.

  The single answer to that question — see
  `KlassHero.Provider.ReadModels.SessionStaffing` for the `:source` fact and
  the lead rule. The projection, the provider UI, and (later) session-level
  authorization all call this rather than re-deriving the fallback.

  Returns `SessionStaffing.empty/2` shaped values for an unknown session, so callers
  rendering a stale row get an empty roster rather than a crash.
  """
  @spec get_session_staffing(String.t()) :: SessionStaffing.t() | nil
  def get_session_staffing(session_id) when is_binary(session_id) do
    [session_id]
    |> list_session_staffing()
    |> Map.get(session_id)
  end

  @doc """
  Batch sibling of `get_session_staffing/1`, keyed by `session_id`.

  Four queries regardless of how many sessions are asked for — sessions, overrides,
  program staffing, and the leads behind them — because the sessions list renders one
  row per session and a per-row call would N+1 exactly where it hurts most.

  Unknown sessions are omitted; `SessionStaffing.staffed_by?/2` and `led_by?/2` both
  accept the resulting `nil` so callers need no defaulting step.
  """
  @spec list_session_staffing([String.t()]) :: %{optional(String.t()) => SessionStaffing.t()}
  def list_session_staffing([]), do: %{}

  def list_session_staffing(session_ids) when is_list(session_ids) do
    sessions = fetch_sessions(session_ids)
    overrides = session_overrides_by_session(Enum.map(sessions, & &1.id))
    program_ids = sessions |> Enum.map(& &1.program_id) |> Enum.uniq()
    program_staffing = Provider.list_program_staffing(program_ids)

    # Over the batch's *distinct* programs, so a full day of sessions costs one
    # closure question rather than one per row (#1082).
    # Unscoped on purpose: the caller hands us session ids, and a session's
    # provider is only knowable by resolving it. `SessionAuthorization` asks
    # this for admins too, so there is no one provider to narrow by.
    open_ids = open_program_ids(program_ids)

    Map.new(sessions, fn session ->
      closed? = not MapSet.member?(open_ids, session.program_id)

      {session.id, resolve_staffing(session, Map.get(overrides, session.id), program_staffing, closed?)}
    end)
  end

  @doc """
  Who a session's read-table row should name: the effective roster's earliest
  active member, with their display name.

  `provider_session_details.current_assigned_staff_*` holds exactly one person
  while a roster holds several, so *some* rule has to pick. This is that rule, in
  one place, for the projection's live path — its bootstrap SQL applies the same
  one in `LATERAL … ORDER BY assigned_at ASC LIMIT 1` form. The two must agree or
  a restart silently rewrites what the events wrote (#1299).

  "Earliest active" rather than "the lead" on purpose: it is what the program-grain
  path already meant, so promoting a lead never moves the name and the two grains
  stay comparable.

  Returns `%{staff_id: nil, staff_name: nil}` when nobody staffs the session —
  including the case where it is overridden to a set of deactivated people, which
  is *not* the same as inheriting the program roster.
  """
  @spec get_session_attribution(String.t()) :: %{staff_id: String.t() | nil, staff_name: String.t() | nil}
  def get_session_attribution(session_id) when is_binary(session_id) do
    with %SessionStaffing{member_ids: [winner | _]} <- get_session_staffing(session_id),
         %StaffMember{} = staff <- Repo.get(StaffMember, winner) do
      %{staff_id: staff.id, staff_name: StaffMember.full_name(staff)}
    else
      _ -> %{staff_id: nil, staff_name: nil}
    end
  end

  @doc """
  Whether `session_id` carries any active override — i.e. whether its staffing is
  its own rather than the program's.

  The projection asks this before applying a *program*-level change: a deliberate
  substitution outranks a roster edit, so re-attributing every scheduled session
  would silently undo it.
  """
  @spec session_overridden?(String.t()) :: boolean()
  def session_overridden?(session_id) when is_binary(session_id) do
    Repo.exists?(
      from a in SessionStaffAssignment,
        where: a.session_id == ^session_id and is_nil(a.unassigned_at)
    )
  end

  @doc """
  The staff members effectively on a session, oldest assignment first.

  The struct-returning companion to `get_session_staffing/1`, for the panel that
  has to render names and headshots rather than reason about ids. Falls through to
  `list_active_staff_for_program/1` when the session inherits, so the two grains
  render from the same shape.
  """
  @spec list_session_staff(String.t()) :: [StaffMember.t()]
  def list_session_staff(session_id) when is_binary(session_id) do
    case get_session_staffing(session_id) do
      nil -> []
      %SessionStaffing{source: :program, program_id: program_id} -> list_active_staff_for_program(program_id)
      %SessionStaffing{member_ids: member_ids} -> staff_in_order(member_ids)
    end
  end

  @doc """
  IDOR-guarded `get_session_staffing/1` for interactive callers.

  The UI opens the staffing panel with this: `session_id` arrives from the client,
  so ownership has to be proven before anything about the session is rendered.
  The unscoped sibling stays for the projection, which has no scope to check.
  """
  @spec get_session_staffing_for_provider(String.t(), String.t()) ::
          {:ok, SessionStaffing.t()} | {:error, :not_found}
  def get_session_staffing_for_provider(provider_id, session_id)
      when is_binary(provider_id) and is_binary(session_id) do
    with {:ok, _session} <- ensure_session_owned(session_id, provider_id) do
      {:ok, get_session_staffing(session_id)}
    end
  end

  @doc """
  The provider's active staff who do not already override `session_id` — the
  addable pool behind the session staffing panel's picker.

  Being on the *program* does not exclude someone: an override names its own
  people, so adding a program member to a session is the ordinary way to say
  "of the three of you, these two work Tuesday".
  """
  @spec list_assignable_staff_for_session(String.t(), String.t()) :: [StaffMember.t()]
  def list_assignable_staff_for_session(provider_id, session_id)
      when is_binary(provider_id) and is_binary(session_id) do
    # Subtracts the *effective* roster, not just the override rows: a session that
    # still inherits is showing the program's team, and offering to "add" someone
    # already on screen is how the picker used to hand out a no-op that read as a
    # roster wipe.
    already_on_session =
      case get_session_staffing(session_id) do
        %SessionStaffing{member_ids: member_ids} -> member_ids
        nil -> []
      end

    from(s in StaffMember,
      where: s.provider_id == ^provider_id and s.active == true,
      where: s.id not in ^already_on_session,
      order_by: [asc: s.first_name, asc: s.last_name]
    )
    |> Repo.all()
    |> Enum.map(&StaffMember.load_pay_rate/1)
  end

  @doc "Lists all active staff assignments for a program."
  @spec list_active_assignments_for_program(String.t()) :: [ProgramStaffAssignment.t()]
  def list_active_assignments_for_program(program_id) when is_binary(program_id) do
    active_assignments_query()
    |> where([a], a.program_id == ^program_id)
    |> Repo.all()
  end

  @doc """
  Lists active staff members assigned to a program.

  Uses a JOIN through `program_staff_assignments` so staff details arrive in a
  single round-trip, ordered by when each assignment was created.
  """
  @spec list_active_staff_for_program(String.t()) :: [StaffMember.t()]
  def list_active_staff_for_program(program_id) when is_binary(program_id) do
    active_staffing_query()
    |> where([assignment: a], a.program_id == ^program_id)
    |> select([staff: s], s)
    |> Repo.all()
    |> Enum.map(&StaffMember.load_pay_rate/1)
  end

  @doc """
  As `list_active_staff_for_program/1`, for the public `/programs/:id` page:
  additionally drops staff who have not claimed their seat.

  A sibling rather than a narrowing of the original, and not a narrowing of
  `active_staffing_query/0` either. Both feed provider-facing surfaces — the
  staffing modal and the programs table — which must keep showing people whose
  invitations are still outstanding. Narrowing the shared base is precisely the
  shape of #1310, where an over-filtered read made staffed programs read as
  "Unassigned" and their staff unfindable.

  Skips `StaffMember.load_pay_rate/1`: no public surface reads a pay rate.
  """
  @spec list_public_staff_for_program(String.t()) :: [StaffMember.t()]
  def list_public_staff_for_program(program_id) when is_binary(program_id) do
    active_staffing_query()
    |> StaffMember.claimed()
    |> where([assignment: a], a.program_id == ^program_id)
    |> select([staff: s], s)
    |> Repo.all()
  end

  @doc """
  Lists the *user* IDs of staff currently active on a program.

  The membership set Messaging needs to answer "does this user act for the
  provider on this program" — for conversation participants and sender
  attribution. Messaging held a mirror of this (`program_staff_participants`)
  until #1321; deriving it is what makes a nil `user_id` unrepresentable (#1309)
  and makes reactivation repair itself with no event, replay, or backfill (#1320).

  Narrower than `list_active_staff_for_program/1` in both directions: it also
  drops staff who have not claimed their invite (no user to name), and it skips
  `StaffMember.load_pay_rate/1`, whose decrypt would otherwise land on a
  per-conversation-mount path for a field no caller here reads.
  """
  @spec list_active_staff_user_ids_for_program(String.t()) :: [String.t()]
  def list_active_staff_user_ids_for_program(program_id) when is_binary(program_id) do
    active_staffing_query()
    |> where([assignment: a, staff: s], a.program_id == ^program_id and not is_nil(s.user_id))
    |> select([staff: s], s.user_id)
    |> Repo.all()
  end

  @doc """
  Lists the *user* IDs of staff who may take part in a program's conversations.

  The program roster **plus** anyone holding an active override on one of the
  program's sessions. Wider than `list_active_staff_user_ids_for_program/1` on
  purpose: `assign_staff_to_session/1` requires only active employment, so a
  substitute covering one Tuesday can hold no `ProgramStaffAssignment` at all and
  was cut off from parent messaging for a session they were running (#784).

  A **union**, not the replacement `get_session_staffing/1` performs, and the
  difference is the question being asked. Attendance asks "may you write *this
  session's* records", so the session's own roster must win — see ADR-0017. A
  conversation is program-scoped and spans every session, so being taken off one
  Tuesday is no reason to lose the thread.
  """
  @spec list_conversation_staff_user_ids_for_program(String.t()) :: [String.t()]
  def list_conversation_staff_user_ids_for_program(program_id) when is_binary(program_id) do
    Enum.uniq(
      list_active_staff_user_ids_for_program(program_id) ++
        session_override_staff_user_ids(program_id)
    )
  end

  # One query rather than "fetch the program's sessions, then their overrides":
  # the session ids are never wanted for themselves, and a term program holds
  # hundreds. Sessions belong to Participation, so the table is named directly
  # inside an `acl_span` (ADR-0015) — the same shape `ParticipationSessionStatsACL`
  # uses, and what `mix lint_acl_boundary` requires of it.
  #
  # Inner join on the staff member, unlike `session_overrides_by_session/1`'s LEFT:
  # that one keeps the override row alive when its member is deactivated so the
  # session does not snap back to the program roster. This one only collects user
  # ids, and a deactivated member contributes none.
  defp session_override_staff_user_ids(program_id) do
    acl_span source: "provider", target: "participation" do
      from(a in SessionStaffAssignment,
        join: sess in "program_sessions",
        on: sess.id == a.session_id,
        join: s in StaffMember,
        on: s.id == a.staff_member_id,
        where: sess.program_id == type(^program_id, :binary_id),
        where: is_nil(a.unassigned_at) and s.active == true and not is_nil(s.user_id),
        select: s.user_id
      )
      |> Repo.all()
    end
  end

  # "Currently staffing a program" — no `unassigned_at`, and the person still
  # employed — in one place, because three reads need exactly this and had each
  # spelled it out. Callers add their own program filter and `select:`; the
  # `:staff` / `:assignment` bindings are named so they can do so positionally
  # without depending on join order.
  defp active_staffing_query do
    from(s in StaffMember,
      as: :staff,
      join: a in ProgramStaffAssignment,
      as: :assignment,
      on: a.staff_member_id == s.id and a.provider_id == s.provider_id,
      where: is_nil(a.unassigned_at) and s.active == true,
      order_by: [asc: a.assigned_at]
    )
  end

  @doc """
  Lists the provider's active staff members who hold no current assignment to
  `program_id` — the addable pool behind the staffing panel's picker.

  Provider-scoped, unlike the display reads above: this answers a *write*
  affordance ("who may I put on this program"), so a rival's staff must never
  appear. Alphabetical, because it renders as a picker rather than a history.

  A retired assignment does not disqualify anyone — `unassigned_at` lifts the
  partial unique index, so a returning staff member is offered again.
  """
  @spec list_assignable_staff_for_program(String.t(), String.t()) :: [StaffMember.t()]
  def list_assignable_staff_for_program(provider_id, program_id)
      when is_binary(provider_id) and is_binary(program_id) do
    from(s in StaffMember,
      as: :staff,
      where: s.provider_id == ^provider_id and s.active == true,
      where: not exists(current_assignment_to(program_id)),
      order_by: [asc: s.last_name, asc: s.first_name]
    )
    |> Repo.all()
  end

  # Correlated EXISTS against the outer :staff binding — cheaper than loading the
  # assigned set and diffing in Elixir, and it keeps "currently assigned" defined
  # in exactly one place (here and `active_assignment_scope/3` agree on
  # `unassigned_at IS NULL`).
  defp current_assignment_to(program_id) do
    from(a in ProgramStaffAssignment,
      where: a.staff_member_id == parent_as(:staff).id,
      where: a.program_id == ^program_id and is_nil(a.unassigned_at),
      select: 1
    )
  end

  @doc "Lists all active staff assignments for a provider."
  @spec list_active_assignments_for_provider(String.t()) :: [ProgramStaffAssignment.t()]
  def list_active_assignments_for_provider(provider_id) when is_binary(provider_id) do
    active_assignments_query()
    |> where([a], a.provider_id == ^provider_id)
    |> Repo.all()
  end

  @doc "Lists all active program assignments for a staff member."
  @spec list_active_assignments_for_staff_member(String.t()) :: [ProgramStaffAssignment.t()]
  def list_active_assignments_for_staff_member(staff_member_id) when is_binary(staff_member_id) do
    active_assignments_query()
    |> where([a], a.staff_member_id == ^staff_member_id)
    |> Repo.all()
  end

  @doc """
  Which programs a staff member may see and act on — every staff surface's
  authorization answer (#1323).

  Selects ids alone rather than reusing
  `list_active_assignments_for_staff_member/1`: the callers gate a render loop and
  need nothing else off the row.

  Takes the `%StaffMember{}` rather than its id, because the tenancy has to arrive
  with it: the programs are then resolved **scoped to that staff member's own
  provider**, so an assignment row naming another provider's program grants
  nothing. Only a caller bypassing `assign_staff_to_program/1` can create such a
  row — that use case proves ownership of both the staff member and the program
  before inserting — but nothing at the database level enforces it, and this is
  the surface where a bad row would become a child's roster.
  """
  @spec get_staff_program_access(StaffMember.t()) :: StaffProgramAccess.t()
  def get_staff_program_access(%StaffMember{id: staff_member_id, provider_id: provider_id}) do
    assigned =
      from(a in ProgramStaffAssignment,
        where: a.staff_member_id == ^staff_member_id and is_nil(a.unassigned_at),
        select: a.program_id
      )
      |> Repo.all()

    {open, closed} = split_by_closure(provider_id, assigned)

    %StaffProgramAccess{
      staff_member_id: staff_member_id,
      program_ids: open,
      closed_program_ids: closed
    }
  end

  # Both sets come from what the query *returned*, never from subtracting one from
  # the assignment list. An assignment naming a foreign or deleted program lands in
  # neither: it grants nothing, and — since `closed_program_ids` is also what the
  # dashboard renders as "Completed" — it is not shown either. Deriving closed as
  # "assigned minus open" would have listed another provider's program back to the
  # staff member.
  defp split_by_closure(provider_id, program_ids) do
    acl_span source: "provider", target: "program_catalog" do
      ProgramCatalog.split_programs_by_closure(provider_id, program_ids)
    end
  end

  defp open_program_ids(program_ids) do
    acl_span source: "provider", target: "program_catalog" do
      ProgramCatalog.list_open_program_ids(program_ids)
    end
  end

  @doc """
  Promotes a staff member to the program's lead instructor — the single source
  of truth for "the lead" (replaces the old `programs.instructor_*` snapshot).

  Idempotent and transactional: any previous lead on the program is cleared and
  the target assignment is flagged lead in one transaction, so the
  `program_staff_assignments_single_lead` partial unique index is never violated
  mid-flight. Creates an active assignment when the staff member has none yet.

  Returns `{:ok, ProgramStaffAssignment.t()}`, or `{:error, :not_found}` when the
  staff member **or the program** is missing or foreign — both sides are checked,
  so a competitor's staff can never attach to this program, nor this provider's
  staff to theirs. A **deactivated** staff member is `{:error, :not_found}` too:
  promoting someone the read side filters out would flag a lead that
  `get_lead_instructor/1` reports as absent (#1306).
  """
  @spec set_lead_instructor(String.t(), String.t(), String.t()) ::
          {:ok, ProgramStaffAssignment.t()} | {:error, :not_found | term()}
  def set_lead_instructor(program_id, staff_member_id, provider_id)
      when is_binary(program_id) and is_binary(staff_member_id) and is_binary(provider_id) do
    context_span entity: "program_staff_assignment" do
      with {:ok, staff_member} <- Provider.get_active_staff_member(staff_member_id, provider_id),
           :ok <- ensure_program_owned(program_id, provider_id) do
        Multi.new()
        |> Multi.update_all(
          :clear_other_leads,
          other_active_leads_query(program_id, staff_member_id, provider_id),
          set: [is_lead_instructor: false]
        )
        |> Multi.run(:lead, fn repo, _ -> upsert_lead(repo, program_id, staff_member, provider_id) end)
        |> Repo.transaction()
        |> case do
          {:ok, %{lead: lead}} -> {:ok, lead}
          {:error, _step, reason, _changes} -> {:error, reason}
        end
      end
    end
  end

  @doc """
  Clears the lead instructor on a program owned by `provider_id`, leaving the
  assignment otherwise active.

  No-op when the program has no lead or is foreign.
  """
  @spec clear_lead_instructor(String.t(), String.t()) :: :ok
  def clear_lead_instructor(program_id, provider_id) when is_binary(program_id) and is_binary(provider_id) do
    active_leads_query(program_id, provider_id)
    |> Repo.update_all(set: [is_lead_instructor: false])

    :ok
  end

  @doc """
  Returns the program's lead instructor as a display map
  (`%{id, name, headshot_url}`), or `nil` when there is no lead.
  """
  @spec get_lead_instructor(String.t()) :: %{id: String.t(), name: String.t(), headshot_url: String.t() | nil} | nil
  def get_lead_instructor(program_id) when is_binary(program_id) do
    lead_staff_query()
    |> where([_s, a], a.program_id == ^program_id)
    |> select([s, _a], s)
    |> Repo.one()
    |> to_lead_map()
  end

  @doc """
  Batch staffing read keyed by `program_id`, for list views that would otherwise
  N+1: every active member of each program plus its lead, in one round-trip.

  Programs nobody staffs are **omitted** rather than mapped to an empty struct —
  callers default with `ProgramStaffing.empty/1`, or pass the `nil` straight to
  `ProgramStaffing.staffed_by?/2`, which accepts it.

  Replaced the lead-only batch read this module used to expose: rendering and
  filtering the provider programs table off the lead alone is what made a
  staffed-but-leaderless program read as "Unassigned" and made non-lead staff
  unfindable in the table's filter (#1310).
  """
  @spec list_program_staffing([String.t()]) :: %{optional(String.t()) => ProgramStaffing.t()}
  def list_program_staffing([]), do: %{}

  def list_program_staffing(program_ids) when is_list(program_ids) do
    active_staffing_query()
    |> where([assignment: a], a.program_id in ^program_ids)
    |> select([staff: s, assignment: a], {a.program_id, s, a.is_lead_instructor})
    |> Repo.all()
    |> Enum.group_by(fn {program_id, _staff, _lead?} -> program_id end)
    |> Map.new(fn {program_id, rows} -> {program_id, to_staffing(program_id, rows)} end)
  end

  defp to_staffing(program_id, rows) do
    lead = Enum.find_value(rows, fn {_program_id, staff, lead?} -> lead? && staff end)
    member_ids = Enum.map(rows, fn {_program_id, staff, _lead?} -> staff.id end)

    %ProgramStaffing{
      program_id: program_id,
      lead: to_lead_map(lead),
      member_ids: member_ids,
      member_count: length(member_ids)
    }
  end

  # Active lead assignment(s) for a program (should be at most one via the index),
  # scoped to the owning provider so no mutation can reach a foreign lead.
  defp active_leads_query(program_id, provider_id) do
    from a in ProgramStaffAssignment.owned_by(provider_id),
      where: a.program_id == ^program_id and a.is_lead_instructor and is_nil(a.unassigned_at)
  end

  # Active leads for the program EXCEPT the incoming staff member — cleared first
  # so promoting a new lead never collides with the partial unique index.
  defp other_active_leads_query(program_id, staff_member_id, provider_id) do
    from a in active_leads_query(program_id, provider_id),
      where: a.staff_member_id != ^staff_member_id
  end

  # Staff joined to their active lead assignment; callers narrow by program and
  # add their own select (single-record vs {program_id, staff} batch).
  #
  # `s.active` matters beyond tidiness: get_lead_instructor/1 feeds the public
  # /programs/:id page, and deactivation is how GDPR erasure retires a staff row.
  defp lead_staff_query do
    from s in StaffMember,
      join: a in ProgramStaffAssignment,
      on: a.staff_member_id == s.id,
      where: a.is_lead_instructor and is_nil(a.unassigned_at) and s.active
  end

  defp upsert_lead(repo, program_id, staff_member, provider_id) do
    case repo.one(active_assignment_scope(program_id, staff_member.id, provider_id)) do
      nil ->
        %ProgramStaffAssignment{}
        |> ProgramStaffAssignment.create_changeset(%{
          provider_id: provider_id,
          program_id: program_id,
          staff_member_id: staff_member.id,
          assigned_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
          is_lead_instructor: true
        })
        |> repo.insert()

      assignment ->
        assignment
        |> ProgramStaffAssignment.lead_changeset(true)
        |> repo.update()
    end
  end

  # The single active (program, staff) assignment for the provider, if one exists.
  defp active_assignment_scope(program_id, staff_member_id, provider_id) do
    from a in ProgramStaffAssignment.owned_by(provider_id),
      where:
        a.program_id == ^program_id and a.staff_member_id == ^staff_member_id and
          is_nil(a.unassigned_at)
  end

  defp to_lead_map(nil), do: nil

  defp to_lead_map(%StaffMember{} = staff) do
    %{id: staff.id, name: StaffMember.full_name(staff), headshot_url: staff.headshot_url}
  end

  # Programs are owned by Program Catalog, so ownership is read through its public
  # facade — strongly consistent, unlike the `provider_programs` projection, whose
  # lag would reject a lead set immediately after the program is created.
  defp ensure_program_owned(program_id, provider_id) do
    acl_span source: "provider", target: "program_catalog" do
      case ProgramCatalog.get_program_for_provider(provider_id, program_id) do
        {:ok, _owned} -> :ok
        {:error, :not_found} -> {:error, :not_found}
      end
    end
  end

  # Sessions are owned by Participation, so the session is read through its public
  # facade and its program checked against `ensure_program_owned/2` — a session is
  # this provider's exactly when its program is. Strongly consistent on purpose: the
  # `provider_session_details` projection lags, so reading ownership from it would
  # reject an override on a session created moments ago.
  #
  # Returns the session itself, not `:ok` — the caller needs its `program_id` for the
  # event payload, and re-reading it would be a second round-trip for a fact already
  # in hand.
  defp ensure_session_owned(session_id, provider_id) do
    acl_span source: "provider", target: "participation" do
      with {:ok, session} <- Participation.get_session(session_id),
           :ok <- ensure_program_owned(session.program_id, provider_id) do
        {:ok, session}
      end
    end
  end

  defp assign_to_session_with_event(assignment_attrs, staff_member, session) do
    Outbox.transact(@context, fn ->
      with :ok <- materialize_program_roster(session, assignment_attrs.provider_id),
           {:ok, assignment} <- insert_session_staff_assignment(assignment_attrs) do
        {:ok, assignment, [Events.staff_assigned_to_session(assignment, staff_member, session.program_id)]}
      end
    end)
  end

  defp unassign_from_session_with_event(session_id, staff_member_id, provider_id, staff_member, session) do
    Outbox.transact(@context, fn ->
      with :ok <- ensure_not_last_member(session_id, staff_member_id),
           :ok <- materialize_program_roster(session, provider_id),
           {:ok, assignment} <- retire_session_staff_assignment(session_id, staff_member_id, provider_id) do
        {:ok, assignment, [Events.staff_unassigned_from_session(assignment, staff_member, session.program_id)]}
      end
    end)
  end

  # The first write to a session that still inherits copies the program's visible
  # roster in *before* the caller's change lands, so "add" adds instead of
  # replacing and "remove" removes one person instead of all but none.
  #
  # This is not the copy-on-create seeding #1321 deleted: rows appear only for a
  # session a human deliberately made different — one session per explicit action,
  # not 500 per program — so the other sessions keep inheriting and there is
  # nothing to reconcile. The cost is stated in the panel: once materialized, later
  # program roster edits no longer reach this session.
  #
  # No events are staged for the copied rows. Consumers re-resolve the whole
  # session through `get_session_attribution/1`, which reads these rows whether or
  # not anything announced them; the one event for the caller's own action is what
  # triggers that re-resolve.
  defp materialize_program_roster(session, provider_id) do
    if session_overridden?(session.id) do
      :ok
    else
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      rows =
        for row <- active_program_roster_rows(session.program_id) do
          %{
            id: Ecto.UUID.generate(),
            provider_id: provider_id,
            session_id: session.id,
            staff_member_id: row.staff_member_id,
            # The *program* assignment's timestamp, not `now`. `assigned_at` is the
            # resolver's sort key and the projection names a session's earliest active
            # member, so stamping the copies with one shared `now` would both make
            # their order arbitrary and place them after the add that triggered the
            # copy — silently renaming the session card. Carrying the program's own
            # timestamps keeps the roster in its original order and correctly ranks
            # everyone who was already there ahead of the person being added.
            assigned_at: row.assigned_at,
            is_lead_instructor: row.is_lead_instructor,
            inserted_at: now,
            updated_at: now
          }
        end

      Repo.insert_all(SessionStaffAssignment, rows)
      :ok
    end
  end

  # Zero override rows means "inherits the program roster", so a session cannot
  # express "deliberately staffed by nobody" — removing the last member would snap
  # the roster back to the full program team. Refuse instead and point at
  # `revert_session_to_program_roster/2`, which is the honest way to say that.
  defp ensure_not_last_member(session_id, staff_member_id) do
    case get_session_staffing(session_id) do
      %SessionStaffing{member_ids: [^staff_member_id]} -> {:error, :cannot_empty_session}
      _ -> :ok
    end
  end

  # The program roster as the panel shows it — active staff only, in assignment
  # order — because materializing must reproduce what the provider was looking at
  # when they clicked.
  defp active_program_roster_rows(program_id) do
    from(a in ProgramStaffAssignment,
      join: s in StaffMember,
      on: s.id == a.staff_member_id and s.active == true,
      where: a.program_id == ^program_id and is_nil(a.unassigned_at),
      order_by: [asc: a.assigned_at, asc: a.id],
      select: %{
        staff_member_id: a.staff_member_id,
        is_lead_instructor: a.is_lead_instructor,
        assigned_at: a.assigned_at
      }
    )
    |> Repo.all()
  end

  defp insert_session_staff_assignment(attrs) do
    %SessionStaffAssignment{}
    |> SessionStaffAssignment.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, assignment} ->
        {:ok, assignment}

      {:error, %Ecto.Changeset{} = changeset} ->
        if EctoErrorHelpers.any_unique_constraint_violation?(changeset.errors) do
          {:error, :already_assigned}
        else
          {:error, changeset}
        end
    end
  end

  defp retire_session_staff_assignment(session_id, staff_member_id, provider_id) do
    session_id
    |> active_session_assignment_scope(staff_member_id, provider_id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      %SessionStaffAssignment{is_lead_instructor: true} ->
        {:error, :cannot_unassign_lead}

      assignment ->
        assignment
        |> SessionStaffAssignment.unassign_changeset()
        |> Repo.update()
    end
  end

  defp revert_session_with_events(session_id, provider_id, session) do
    Outbox.transact(@context, fn ->
      doomed =
        from(a in SessionStaffAssignment.owned_by(provider_id),
          join: s in StaffMember,
          on: s.id == a.staff_member_id,
          where: a.session_id == ^session_id and is_nil(a.unassigned_at),
          select: {a, s}
        )
        |> Repo.all()

      {count, _} =
        from(a in SessionStaffAssignment.owned_by(provider_id),
          where: a.session_id == ^session_id and is_nil(a.unassigned_at)
        )
        |> Repo.update_all(
          set: [
            unassigned_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
            is_lead_instructor: false
          ]
        )

      # One event per retired row rather than a single "reverted" event: consumers
      # already key on (session, staff member), and #784 will want that granularity
      # to decide whose messaging membership changed.
      events =
        Enum.map(doomed, fn {assignment, staff_member} ->
          Events.staff_unassigned_from_session(assignment, staff_member, session.program_id)
        end)

      {:ok, count, events}
    end)
  end

  # Still no insert branch, unlike the program-level `upsert_lead/4` — but for a
  # different reason now. Materialization has already put every roster member on the
  # session, so a miss here means the target genuinely is not on it, and inserting
  # would be promoting a stranger rather than repairing a gap.
  defp promote_session_lead(repo, session_id, staff_member_id, provider_id) do
    case repo.one(active_session_assignment_scope(session_id, staff_member_id, provider_id)) do
      nil ->
        {:error, :not_found}

      assignment ->
        assignment
        |> SessionStaffAssignment.lead_changeset(true)
        |> repo.update()
    end
  end

  defp other_active_session_leads_query(session_id, staff_member_id, provider_id) do
    from a in SessionStaffAssignment.owned_by(provider_id),
      where:
        a.session_id == ^session_id and a.staff_member_id != ^staff_member_id and
          a.is_lead_instructor and is_nil(a.unassigned_at)
  end

  # Sessions belong to Participation, so they are read through its facade (ADR-0015)
  # rather than joined to from here — which is also why the resolver cannot be one
  # SQL statement.
  defp fetch_sessions(session_ids) do
    acl_span source: "provider", target: "participation" do
      Participation.get_sessions(session_ids)
    end
  end

  # Every active override for these sessions, with the staff member LEFT-joined on
  # `active`. Left, not inner, because the two facts differ: the *row* existing is
  # what makes a session overridden, while the staff member being active is what
  # makes them a member. An inner join would collapse them, and a session whose only
  # substitute was later deactivated would silently fall back to the program roster —
  # resurrecting exactly the people the provider took off that day.
  defp session_overrides_by_session([]), do: %{}

  defp session_overrides_by_session(session_ids) do
    from(a in SessionStaffAssignment,
      left_join: s in StaffMember,
      on: s.id == a.staff_member_id and s.active == true,
      where: a.session_id in ^session_ids and is_nil(a.unassigned_at),
      order_by: [asc: a.assigned_at, asc: a.id],
      select: {a.session_id, a.is_lead_instructor, s}
    )
    |> Repo.all()
    |> Enum.group_by(fn {session_id, _lead?, _staff} -> session_id end)
  end

  # Ordered by the caller's ids, not by the query: `member_ids` already carries the
  # earliest-assigned-first order the attribution rule depends on, and an `IN` gives
  # no order at all.
  defp staff_in_order(member_ids) do
    by_id =
      from(s in StaffMember, where: s.id in ^member_ids)
      |> Repo.all()
      |> Map.new(&{&1.id, StaffMember.load_pay_rate(&1)})

    for id <- member_ids, staff = by_id[id], do: staff
  end

  defp resolve_staffing(session, nil, program_staffing, closed?) do
    inherited_staffing(session, program_staffing, closed?)
  end

  defp resolve_staffing(session, override_rows, program_staffing, closed?) do
    members = for {_id, _lead?, staff} <- override_rows, staff != nil, do: staff

    %SessionStaffing{
      session_id: session.id,
      program_id: session.program_id,
      lead: resolve_session_lead(override_rows, members, session.program_id, program_staffing),
      member_ids: Enum.map(members, & &1.id),
      member_count: length(members),
      source: :override,
      program_closed?: closed?
    }
  end

  defp inherited_staffing(session, program_staffing, closed?) do
    case Map.get(program_staffing, session.program_id) do
      nil ->
        SessionStaffing.empty(session.id, session.program_id, closed?)

      %ProgramStaffing{} = staffing ->
        %SessionStaffing{
          session_id: session.id,
          program_id: session.program_id,
          lead: staffing.lead,
          member_ids: staffing.member_ids,
          member_count: staffing.member_count,
          source: :program,
          program_closed?: closed?
        }
    end
  end

  # Session lead first; failing that, the program lead — but only when they are
  # actually working this session. Naming an absent lead is the worse failure: the
  # roster would claim supervision nobody is providing.
  defp resolve_session_lead(override_rows, members, program_id, program_staffing) do
    flagged = Enum.find(override_rows, fn {_id, lead?, staff} -> lead? and staff != nil end)

    case flagged do
      {_id, _lead?, staff} -> to_lead_map(staff)
      nil -> inherited_lead(members, program_id, program_staffing)
    end
  end

  defp inherited_lead(members, program_id, program_staffing) do
    with %ProgramStaffing{lead: %{id: lead_id} = lead} <- Map.get(program_staffing, program_id),
         true <- Enum.any?(members, &(&1.id == lead_id)) do
      lead
    else
      _ -> nil
    end
  end

  # The single active (session, staff) override for the provider, if one exists.
  defp active_session_assignment_scope(session_id, staff_member_id, provider_id) do
    from a in SessionStaffAssignment.owned_by(provider_id),
      where:
        a.session_id == ^session_id and a.staff_member_id == ^staff_member_id and
          is_nil(a.unassigned_at)
  end

  # The assignment and the event announcing it commit together; the outbox job then
  # delivers to everything routed from integration:provider:staff_(un)assigned_*,
  # with the event-id idempotency gate preventing double execution on retry.
  defp assign_with_event(assignment_attrs, staff_member) do
    Outbox.transact(@context, fn ->
      with {:ok, assignment} <- insert_program_staff_assignment(assignment_attrs) do
        {:ok, assignment, [Events.staff_assigned_to_program(assignment, staff_member)]}
      end
    end)
  end

  defp unassign_with_event(program_id, staff_member_id, provider_id, staff_member) do
    Outbox.transact(@context, fn ->
      with {:ok, assignment} <- unassign_program_staff_assignment(program_id, staff_member_id, provider_id) do
        {:ok, assignment, [Events.staff_unassigned_from_program(assignment, staff_member)]}
      end
    end)
  end

  # An INSERT can't carry a query scope, so the row's tenancy key is taken from
  # the ownership-proven staff member rather than the caller's attrs — the same
  # rule `upsert_lead/4` follows.
  defp build_assignment_attrs(attrs, %StaffMember{provider_id: provider_id}) do
    attrs
    |> Map.put(:assigned_at, DateTime.utc_now())
    |> Map.put(:provider_id, provider_id)
  end

  defp insert_program_staff_assignment(attrs) do
    %ProgramStaffAssignment{}
    |> ProgramStaffAssignment.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, assignment} ->
        {:ok, assignment}

      {:error, %Ecto.Changeset{} = changeset} ->
        if EctoErrorHelpers.any_unique_constraint_violation?(changeset.errors) do
          {:error, :already_assigned}
        else
          {:error, changeset}
        end
    end
  end

  defp unassign_program_staff_assignment(program_id, staff_member_id, provider_id) do
    program_id
    |> active_assignment_scope(staff_member_id, provider_id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      %ProgramStaffAssignment{is_lead_instructor: true} ->
        {:error, :cannot_unassign_lead}

      assignment ->
        assignment
        |> ProgramStaffAssignment.unassign_changeset()
        |> Repo.update()
    end
  end

  # Active assignments (never unassigned), oldest-first — shared base for the
  # three list_active_assignments_* reads above.
  defp active_assignments_query do
    from a in ProgramStaffAssignment,
      where: is_nil(a.unassigned_at),
      order_by: [asc: a.assigned_at]
  end
end
