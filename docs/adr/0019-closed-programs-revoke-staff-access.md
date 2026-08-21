# Closed Programs revoke staff access, at the read model

A **Staff Member** loses access to a Program once it has been over for longer than a grace
window. The rule is applied where the Provider read models are *built*, not at the surfaces
that ask them, so no caller has to know it exists.

```elixir
# Program grain — Assignments.get_staff_program_access/1
%StaffProgramAccess{
  program_ids: assigned ∩ open,          # authorized?/2 answers from this
  closed_program_ids: assigned \ open    # closed?/2 answers from this
}

# Session grain — Assignments.list_session_staffing/1
%SessionStaffing{program_closed?: true}  # staffed_by?/2 and led_by?/2 return false
```

Closed is **derived**, not stored: `end_date < today - closed_after_days`, with a `nil`
`end_date` meaning a program never closes. The window is
`config :klass_hero, :program_access, closed_after_days: 14`.

## Why

Before #1082 nothing consulted `end_date` for authorization. A staff member assigned to a
program that finished a year ago could still open a child's roster, check a child in or out,
correct an attendance record, and broadcast to the enrolled parents. The people this most
concerns are ex-collaborators who were deactivated rather than offboarded, whose Program
Staff Assignments deliberately survive so a reversible pause does not destroy conversation
access.

The issue asked for the four staff LiveViews to filter closed programs out. That would have
put one authorization rule in four places and left the fifth — `Participation`'s write path,
the guard of record since ADR-0017 — accepting the writes the UI had stopped offering. It
would also have missed `StaffBroadcastLive` entirely.

That shape is the one #1323 removed. There, whether you could check a child in and out
depended on a `staff_members.tags` string matched against `program.category`, re-derived at
each of four surfaces, with an empty tag list silently meaning *every* program. The fix was
one struct, built in one place. Adding a second rule that each surface must remember to
apply would have re-created the failure with a different input.

So closure is folded into the same two structs. Four of the five call sites did not change
at all and became correct:

| Surface | Change |
|---|---|
| `Participation.AttendanceAuthorization` | none |
| `StaffBroadcastLive` | none |
| `StaffDashboardLive` roster handler | none |
| `StaffSessionsLive` list + action gate | none for the gate; message copy only |
| `StaffParticipationLive` | message copy only |

## The costs, taken deliberately

**`StaffProgramAccess` no longer means one thing.** Its moduledoc said it was derived from
assignment rows and nothing else. It is now assignment rows narrowed by closure. Both are
write-model facts a provider controls, and closure is read from `programs` through
`ProgramCatalog.list_open_program_ids/1`, never from the `program_listings` projection —
projection lag must not revoke access.

**Every `SessionStaffing` consumer pays a query.** `list_session_staffing/1` asks
ProgramCatalog once per batch, over the distinct program ids, so a full day of sessions costs
one extra query rather than one per row. But provider-side callers that read only
`member_ids` or `lead` pay it too and can never use the answer. The alternative — closure as
an extra argument only authorization call sites pass — makes the query conditional and
re-opens the hole: a future call site that omits the argument authorizes on a closed program,
with nothing to catch it. We would rather waste the query.

**It fails closed.** `list_open_program_ids/1` returns the ids that exist *and* are open, and
callers derive closed by set difference, so an assignment naming a program that no longer
resolves grants nothing.

## What is not gated

Providers and Admins. The provider owns the roster and must still correct it after a season
ends; an admin correction still demands its written reason. ADR-0017's fall-through order —
provider, then staff, then admin — is untouched, and only the staff branch's answer narrowed.

The `SessionStaffing` display fields (`member_ids`, `member_count`, `lead`, `overridden?/1`)
are also untouched, so the provider's own staffing panel keeps working on a closed program.
Only the two predicates that answer authorization questions are gated.

## Why 14 days and its own config key

The window has to outlast the honest tail of a season: a late check-out, a correction the
morning after the last session, a closing message to parents. It should not outlast a
departed collaborator's interest in a child's record.

Messaging already carries `days_after_program_end: 30`, and closure deliberately does **not**
reuse it. That window decides when a conversation is archived for data retention; this one
decides when a person stops being allowed to see a child's record. They coincide in shape
today and would be changed for different reasons tomorrow.

## Consequences

- Adding a staff surface requires no new closure check, provided it asks
  `StaffProgramAccess.authorized?/2` or `SessionStaffing.staffed_by?/2`. A surface that
  re-derives access from `end_date` itself, or from `program_listings`, is a bug.
- `CONTEXT.md`'s **Program Staff Assignment** entry no longer says an assignment is the only
  thing deciding what a staff member sees; it is now the assignment, while the program is open.
- A refusal can say *which* rule refused, because `program_closed?` rides on the struct the
  surface already fetched. No extra query buys the better message.
