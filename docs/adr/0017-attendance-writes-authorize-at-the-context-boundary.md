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
resolved by `Participation.AttendanceAuthorization`.

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
deterministic answer. `AttendanceAuthorization.authorize/2` takes the first that matches:

| Order | Rule | Cost |
|---|---|---|
| 1. provider | the scope's provider owns the session's program | 1 query (`ProgramProviderResolver`) |
| 2. staff | the scope's staff member is assigned to it (`StaffProgramAccess`, #1323) | 1 query |
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
