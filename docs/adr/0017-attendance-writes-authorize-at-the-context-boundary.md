# Attendance writes authorize at the context boundary

Checking a child in or out, and correcting an attendance record, are authorized inside
`KlassHero.Participation` — against the caller's `Accounts.Scope`, at the point of the write.
The web layer's own checks remain, as defence in depth rather than as the guarantee.

The public interface takes the scope and derives everything else from it:

```elixir
Participation.record_check_in(scope, record_id, notes: notes)
Participation.record_check_out(scope, record_id, notes: notes)
Participation.correct_attendance(scope, record_id, attrs)
```

No caller names the actor or declares its own role any more. `checked_in_by`, `checked_out_by`
and `actor_role` are gone from the interface; identity is `scope.user.id` and the role is
resolved by `Participation.SessionAuthorization`.

## Why

Before #1353 these functions authorized nothing. They accepted a user id and *recorded* it, and
`correct_attendance` accepted an `actor_role` and believed it. The only thing between an actor
and any child's attendance record was the web layer — and not a check even there. The handler
looked the record up with `Enum.find` over `socket.assigns.participation_records`, a roster an
authorized query had loaded at mount. The guard was **emergent from the load path** and stated
nowhere; nothing in the handler looked like a check, because nothing was one.

That is a guarantee only the existing callers happened to provide. `bulk_check_in/1` already
showed the cost: public, ungated, taking a *list* of record ids, with zero production callers.
The "one non-LiveView caller away" scenario was half-materialized on the widest write path
before anyone wrote that caller. It was deleted here rather than gated.

This is the child-safety surface. Check-out records who collected a child. A guard that lives in
one of four callers is not a guard.

## The fall-through order

A person is one User and may hold several personas at once, so *which* rule applies needs a
deterministic answer. `SessionAuthorization.authorize/2` takes the first that matches:

| Order | Rule | Cost |
|---|---|---|
| 1. provider | the scope's provider owns the session's program | 1 query (`ProgramProviderResolver`) |
| 2. staff | the scope's staff member is on the session (`SessionStaffing`, #783) | 4 queries |
| 3. admin | `scope.user.is_admin` | none |
| else | `{:error, :unauthorized}` | — |

Narrow to broad, mirroring the precedence `KlassHeroWeb.RoleRouting.primary_role/1` already
uses. The order is load-bearing, not alphabetical, because the derived role also selects
*behaviour*: an `:admin` correction demands a reason and appends it to the notes, while a
provider or staff member correcting their own roster does not.

So an admin who also owns a provider gets **provider** rules on their own programs — correct,
they are the provider, and demanding a written justification from someone editing their own
roster would be absurd — and falls through to **admin** rules only on programs they do not own,
where a reason *is* demanded. Admin-first would invert exactly this.

A staff member with no assignment is authorized for nothing, per `StaffProgramAccess`'s own
rule: assignment is a deliberate act, so "not assigned yet" and "not allowed" are the same fact.

## Amended by #783: the staff rule is asked at session grain

`authorize/2` takes the session, not its program id. The provider and admin branches still read
`session.program_id` — ownership and the admin flag are program-wide facts — but the staff
branch asks `Provider.get_session_staffing/1`, which returns a session's own overrides when it
has any and falls back to the program roster when it does not.

This is one question with the program grain as its *fallback*, not two rules OR-ed together, and
the difference is not cosmetic. #782 lets a provider take one person off a single session:
`unassign_staff_from_session/3` materializes the program roster onto that session and drops them
from it, deliberately leaving their `ProgramStaffAssignment` intact. Under an OR they would keep
authorizing on the program row — the removal silently undone at the layer meant to enforce it.
Asking the resolver instead means the two grains cannot disagree, because only one of them is
ever consulted.

The cost is the staff row above: `get_session_staffing/1` resolves sessions, overrides, program
staffing and leads, so the branch went from one query to four, and one of them re-reads a
session Participation already holds (`Assignments.fetch_sessions/1` calls back through
`Participation.get_sessions/1`). Acceptable on a write path that already fetches the record and
its session. Not acceptable per row — which is why the staff sessions list uses the batch
`list_session_staffing/1`, four queries regardless of how many sessions the day holds.

## Amended by #784: messaging unions the two grains instead

Messaging combines the same two grains with the opposite operator.
`Provider.list_conversation_staff_user_ids_for_program/1` returns the program roster **plus**
everyone holding an active override on one of the program's sessions, and Messaging seeds
conversation participants from that union.

The operator follows the artifact, not a house style. Attendance authorizes a write against **one
session**, so exactly one roster can be the right answer and a fallback is the honest way to pick
it — which is the whole argument two sections up. A conversation is **program-scoped**: there is
no `conversations.session_id`, and there is no per-session thread to be excluded from. Its
question is "may you talk to this program's parents", and someone running any one of its sessions
may. Being taken off a single Tuesday is a reason to lose that Tuesday's attendance rights; it is
not a reason to lose the thread.

The union is also what closes #784 at all. `assign_staff_to_session/1` requires only active
employment, never a `ProgramStaffAssignment`, so a substitute can hold no program-level row —
under replacement semantics the program conversation would simply never see them.

The cost is a second removal rule. One retired row no longer settles whether someone leaves, so
`StaffAssignmentHandler` re-asks the union before evicting anyone, in both directions. Without
that, unassigning someone from the program would evict them from conversations for a session they
still run — #784 through the opposite door — and it is the exact mirror of the failure OR-ing
would have caused here.

## Amended by #1373: session lifecycle joined the gate, and refusals name their reason

`start_session/1` and `complete_session/1` were never brought in. They took a bare session
id and authorized nothing, which meant the provider sessions list handed a client-supplied
`phx-value-session_id` straight to a write that marks **every remaining registered child
absent**. Staff was covered only because `StaffSessionsLive` had hand-rolled
`authorize_session_action/2` in the LiveView — the same "guard that lives in one of four
callers" this ADR rejected, re-grown on the write path it did not cover.

Both now take the scope:

```elixir
Participation.start_session(scope, session_id)
Participation.complete_session(scope, session_id)
```

The module was renamed `AttendanceAuthorization` → **`SessionAuthorization`**, because it
now answers two questions rather than one, and both are about a `ProgramSession`. It holds
a single private `resolve/2` — the fall-through above, unchanged — under two entry points:

| Entry point | Refusals |
|---|---|
| `authorize/2` | always `:unauthorized` |
| `authorize_lifecycle/2` | `:unauthorized` or `:program_closed` |

**The narrowing is the design, not a leftover.** Widening `authorize/2` itself was smaller
and wrong: `:program_closed` would reach the attendance path, where
`ParticipationLiveHandlers` matches only `{:error, :unauthorized}` and everything else falls
to `"Failed to check in: …"`. A closed-program check-in would silently change its message,
compile clean, and break no test. So attendance keeps the contract it has, and the ~10
assertions in `session_authorization_test.exs` pass untouched — which is how we know it kept
it.

Only the lifecycle path needs the distinction, and only because the staff sessions list has
said "This program has closed." since #1082 and should keep saying it.

### The reason is narrower than the rule

`Provider.get_session_staffing/1` answers for **any** session id. A reason read off
`program_closed?` alone would therefore tell any staff-persona caller the closure state of a
program they had merely guessed an id for — a disclosure introduced by the change that closes
the IDOR. `refused_for_closure?/2` asks instead whether the caller is in `member_ids`, which
ADR-0019 deliberately left ungated, so `:program_closed` means *you would have been staff,
but the program closed*. A stranger gets a bare `:unauthorized`.

Closure is also asked **after** the admin branch. It is a staff rule, and asking it earlier
would take the broader persona from someone who holds both.

### Consequences

- `StaffSessionsLive.authorize_session_action/2` is deleted; both sessions lists are now the
  same three-clause `case`. `staffs_session?/2` stays — it filters PubSub messages.
- The closed-program sentence lived at three call sites as a literal. It is now
  `ParticipationLiveHandlers.session_refusal_message/1`.
- Providers and admins remain ungated by closure (ADR-0019). A provider completing their own
  Closed Program's session is pinned by tests at both the authorizer and the use case.
- **A refusal must not say whether the session exists.** Authorizing at the context boundary
  means resolving the session *first*, so `:not_found` and `:unauthorized` become two
  distinguishable answers to a caller who supplied the id — an enumeration oracle the deleted
  LiveView guard had closed by accident, by treating every lookup failure as a refusal.
  `ParticipationLiveHandlers.session_refusal_message/1` answers both identically. The reason
  still reaches the log; only the user-visible answer is flattened. Any future write that
  takes a client-supplied id and authorizes after fetching inherits this problem.

## Amended by #1329: session notes joined the gate

The three Session Note writes were never brought in, and one of them had no guard of any
kind. All three now take the scope:

```elixir
Participation.submit_session_note(scope, %{participation_record_id: id, content: content})
Participation.review_session_note(scope, %{note_id: id, decision: decision, reason: reason})
Participation.revise_session_note(scope, %{note_id: id, content: content})
```

`submit_session_note/1` was the worst write on this surface, worse than the pre-#1353
attendance functions this ADR was written about. Those at least *recorded* the id they were
handed. This one accepted a `provider_id`, stamped it onto a note about any record id it was
also handed, and checked neither against anything — no authorizer, and not even the
DB-scoped fetch its two siblings had. Any caller could write a note about any child in any
provider's name. Its test file asserted the hole rather than catching it: every passing test
supplied an unrelated provider, one of them a bare `Ecto.UUID.generate()`.

It now authorizes through `SessionAuthorization.authorize/2` on the record's session — the
same question as check-in, because it is the same surface — and then derives the authoring
provider from the granted role rather than from the caller.

### Admin is authorized for the session and still refused the note

`authorize/2` grants `:admin`, and `submit_session_note/2` refuses it anyway. This is the
first place the derived role and the write come apart, and deliberately: the role answers
*may you act on this session*, while a Session Note additionally needs *whose note is this*.
`CONTEXT.md` defines one as the **Instructor's** routine feedback, and an admin holds no
provider identity to author it under. Deriving `provider_id` from the role is what surfaces
the question — the old signature could not ask it, because the caller simply supplied an
answer.

### The two ownership rules are not the same rule

`review` and `revise` are not session writes and do not go through `authorize/2`:

| Write | Question | Asked of |
|---|---|---|
| `submit` | may you act on this session, and as whom? | `SessionAuthorization` |
| `review` | is this note about one of your children? | `Family.get_child_ids_for_parent/1` |
| `revise` | are you its author? | the note's own `provider_id` |

`review` used to ask a third thing — `WHERE session_notes.parent_id = $1` — and that column
is written by nothing. Every note in production carried a NULL parent, so the query matched
nothing and **no parent had ever seen a pending note, let alone approved one**. The rule now
goes through the child, which Family owns and answers (ADR-0015), so there is no denormalised
copy to be NULL, and none to go stale when a child's guardian changes.

That is also why the fix needed no backfill: the notes were never mis-written, only
mis-queried.

### The enumeration oracle, again

Both `review` and `revise` fetch before they authorize, so they inherit the problem the #1373
section names above: `:not_found` and `:unauthorized` become distinguishable to a caller who
supplied the id. The parent surface already flattens them — `approve_note` and `reject_note`
render one flash for every error — so the distinction reaches the log and not the user. Any
new note surface must keep it that way.

## Derived, not declared

`is_admin` lives on the user and is deliberately absent from `registration_changeset`'s cast
list, so no request can grant it to itself. Reading it from the scope costs nothing and cannot
be spoofed; accepting an `actor_role` parameter, as `correct_attendance` did, trusted the caller
to report a fact about itself. Attribution follows the same reasoning as message attribution in
#1348: once you must prove who you are in order to write, there is nothing left for the caller
to assert.

## What stays in the web layer

The mount-time gates in `StaffParticipationLive` and `Provider.ParticipationLive` remain. They
serve a different purpose — they keep an unauthorized roster off the screen and redirect, rather
than rendering a page whose every button will fail. `find_participation_record/2` also stays,
for its "Record not found" flash and the `child_id` on the failure log. Neither is load-bearing
for authorization now, and both say so where they are defined.

## Consequences

- Cross-context reads: Participation calls `Provider.get_staff_program_access/1` directly and
  reuses its own `ProgramProviderResolver` ACL. Both are ADR-0015-conformant; no new adapter.
- Two extra queries per attendance write, worst case (session lookup, then one role check).
- A caller cannot pass a bare user id any more: the `%Scope{}` guard rejects it at the head.
- `bulk_check_in/1` is gone. A future bulk check-in UI should reintroduce it behind the same
  authorizer, not restore the old shape.
