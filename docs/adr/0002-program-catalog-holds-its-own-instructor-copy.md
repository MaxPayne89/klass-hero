# Program Catalog holds its own Instructor copy (ACL snapshot)

> **Superseded by [ADR 0008](0008-lead-instructor-single-source-of-truth.md) (2026-07-09).**
> The `programs.instructor_*` snapshot columns, the `Instructor` value object, and the
> `program_listings.instructor_*` projection copy were removed. The lead instructor is now
> the single source of truth on `program_staff_assignments.is_lead_instructor`, read live
> via the `Provider` facade. The staleness/rename-propagation hazard below no longer applies.

Program Catalog does not depend on the Provider context's richer `StaffMember` type. Each Program embeds an `Instructor` value object — a minimal `{id, name, headshot_url}` snapshot copied from Provider data at write time — acting as an Anti-Corruption Layer so Provider's model cannot leak into the catalog.

The trade-off is staleness: the snapshot can drift if the underlying Staff Member is renamed or re-photographed. It must therefore be refreshed via events and treated as a derived display copy, not the authoritative record — the same denormalisation hazard as the projected `program_name`.

## Consequences

- Renames in Provider must propagate to the catalog snapshot through events, not be assumed live.
- The catalog shows a single lead Instructor; the full assigned team lives in Provider's `ProgramStaffAssignment` and is not mirrored here.
