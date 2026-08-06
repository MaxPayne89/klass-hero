# Lead instructor is a single source of truth on program_staff_assignments

**Date:** 2026-07-09 · **Supersedes:** [ADR 0002](0002-program-catalog-holds-its-own-instructor-copy.md) · **Issue:** #840

## Context

The lead instructor of a program was held in two denormalised snapshots:

- `programs.instructor_id/_name/_headshot_url` + the `ProgramCatalog.Instructor` value
  object (ADR 0002's ACL copy), and
- `program_listings.instructor_name/_headshot_url` (a CQRS projection copy feeding the
  provider dashboard table).

Meanwhile Provider already models program↔staff links in `program_staff_assignments`.
The same person could be reached through both paths, producing duplicate "hero" cards on
the program detail page (patched at the UI layer by a `HeroCardsPresenter` dedup in #796),
and both snapshots could drift when a staff member was renamed or re-photographed.

This also fought the prevailing direction (#1027) of reading cross-context data live
through the owning context's facade rather than denormalising it.

## Decision

The lead instructor is the staff member whose `program_staff_assignments` row carries
`is_lead_instructor` — a single source of truth owned by Provider. A partial unique index
(`program_id WHERE is_lead_instructor AND unassigned_at IS NULL`) enforces at most one
active lead per program.

- Provider exposes `set_lead_instructor/2`, `clear_lead_instructor/1`, `get_lead_instructor/1`,
  and a batch `list_lead_instructors_for_programs/1`.
- ProgramCatalog holds **no** instructor data: the `programs.instructor_*` columns, the
  `Instructor` value object, and the `program_listings.instructor_*` projection columns are
  removed. Name/headshot are read live from the `Provider` facade at display time.
- The provider program form's existing instructor picker writes the lead assignment on save
  (a thin two-call shell: `ProgramCatalog.create/update_program` → `Provider.set_lead_instructor`).

## Consequences

- **No drift, no dedup:** name/headshot are always live; the `HeroCardsPresenter` merge logic
  and `InstructorPresenter` are deleted. `HeroCardsPresenter` is a straight presenter that puts
  the lead card first with a "Lead Instructor" badge.
- **Absorbs #896:** rename propagation dissolves — there is no snapshot to refresh.
- **Cross-context read on the display path:** program detail and the provider table read the
  lead via the `Provider` facade (the detail page already read Provider staff there). The
  provider table uses the batch read to avoid N+1.
- **Cross-context write orchestration:** program save now touches both contexts. Kept as a thin
  LiveView shell (lead is optional; a failed lead-set leaves a valid program). Extract a
  coordinator only if it grows.
- **Trade-off accepted:** ProgramCatalog now depends on the Provider facade for instructor
  display, reversing ADR 0002's isolation — a deliberate choice favouring a single source of
  truth over context isolation for this read, consistent with #1027.
