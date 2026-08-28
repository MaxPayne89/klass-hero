---
name: architecture-reviewer
description: >-
  Review code changes for conventional-Phoenix convention compliance
  (post-flatten). Checks schema-as-struct integrity, absence of reintroduced
  ports/DI/Boundary, cross-context-via-facade access, and correct placement of
  the surviving CQRS/event/worker/ACL subdirectories. Run as a subagent for
  architecture validation.
---

# Architecture Reviewer

Validate that code changes follow the project's **conventional Phoenix** conventions.

All 7 bounded contexts were flattened from DDD/Ports & Adapters to conventional
Phoenix (#986–#1002); the `boundary` library was removed and per-context DI/port
wiring was deleted. This agent checks that new code follows the flattened
convention and does NOT reintroduce the removed layering.

**Type:** Checklist-based review. Evaluate each rule, report violations.

---

> **Migration window (read before running checks 5–8).** A repo-wide flatten is
> in progress: `accounts`, `provider`, `family` and `messaging` have been
> converted to the new one-level layout below; the other three contexts
> (participation, enrollment, program_catalog) and `shared` still carry the old
> `adapters/{driven,driving}/` + `domain/` tree. **Both shapes are legal at
> once** until the migration finishes — never flag an unconverted context for
> keeping the old tree, and never flag a converted one for lacking
> `adapters/`/`domain/`. Checks below identify a kind by
> what it **is** (a `use`/behaviour/naming signature) first, then accept
> either shape's legal location — a check written as "for each file in
> `adapters/driven/projections/`" would pass vacuously on a flattened context
> and must not be trusted on its own.

## Context

Bounded contexts under `lib/klass_hero/`:
Accounts, Family, Provider, ProgramCatalog, Enrollment, Messaging, Participation, Shared, Admin.

**Flattened shape** (`accounts` today; others convert one PR at a time):
```
context.ex                  # Public API — the ONLY module other contexts call
context/
├── <entity>.ex             # Schema-as-struct: Ecto schema + struct + functional core
│                           #   (validators, state machines). e.g. provider/staff_member.ex
├── <read_table>.ex         # Projection read-table schema: IS the DTO, no changeset —
│                           #   the projection owns every write. e.g. provider/session_detail.ex
├── <use_case>.ex           # Command/query modules at the root
├── events.ex               # Factory for this context's integration events
├── <handler>.ex            # Consumes another context's events — named for what it
│                           #   consumes, NOT filed under an events/ dir
├── <worker>.ex             # Oban worker
├── projections/            # CQRS projection GenServers          (3+ files)
├── workers/                # Oban workers                         (3+ files)
├── acl/                    # Cross-context read adapters          (3+ files)
├── notifications/          # Email/notification senders           (3+ files)
├── queries/                # Composable write-side query builders (3+ files)
└── read_models/            # Query-shaped structs over WRITE tables (3+ files)
```
A kind gets its own directory only at 3+ files; below that its modules sit at the
context root. There is no `adapters/` or `domain/` layer in this shape.

**Old DDD-derived shape** (still: provider, family, messaging, participation,
enrollment, program_catalog, shared):
```
context.ex
context/
├── <entity>.ex
├── <read_table>.ex
├── <use_case>.ex           #   some contexts also use application/commands|queries/
├── domain/
│   ├── events/             # Domain & integration event structs (pure), one per file
│   └── read_models/        # Query-shaped plain structs over WRITE tables (no logic,
│                           #   no Ecto schema, no read table of their own)
└── adapters/
    ├── driven/{projections,persistence,acl,notifications}/
    └── driving/{events,workers}/
```

**Survivors** (legitimate in either shape): projection GenServers, read models (CQRS),
composable write-side query builders, ACL adapters (cross-context reads), notification
senders, event handlers, Oban workers, and the event-struct factory/files.

Projection read **tables** do NOT live under `persistence/`/`queries/` — their schema sits at
the context root and is the DTO (see the trees above), in both shapes.
`adapters/driven/persistence/{repositories,schemas}/` survives in **Shared only**, for the
event and job infrastructure tables (`processed_events`, `job_compensations`,
`undelivered_events`); no bounded context has a repository left.

**Removed** (flag if reintroduced, regardless of shape): `domain/models/`, `domain/ports/`,
`application/use_cases/`, persistence mappers for aggregates, `use Boundary`,
per-context `for_*` DI wiring in `config/config.exs`.

---

## Check 1: Schema-as-struct integrity

**Rule:** A new entity is ONE module at the context root that `use Ecto.Schema`,
exposes changesets, and carries its functional core (pure business logic —
validators returning `{:error, [message]}`, state machines, formatters).

**How to verify:**
1. For each new/changed entity module at a context root (`lib/klass_hero/<ctx>/<entity>.ex`)
2. Confirm it `use Ecto.Schema` and defines changeset function(s)
3. Confirm pure logic lives in the same module (not split into a separate `domain/models/` struct)

**Not an entity — skip it:** a projection read-table schema also sits at the context root and
also `use Ecto.Schema`, but has **no changeset on purpose** (the projection owns every write).
Its moduledoc says so. Do NOT flag a missing changeset there — that is the correct shape, not a
violation. e.g. `provider/session_detail.ex`, `messaging/conversation_summary.ex`.

**Violations to flag:**
- A new aggregate split into `domain/models/<x>.ex` (struct) + `adapters/.../schemas/<x>_schema.ex` (schema) + a mapper — this is the removed DDD pattern
- Reference: `lib/klass_hero/provider/staff_member.ex`

## Check 2: No reintroduced Boundary

**Rule:** The `boundary` library was removed. No module should declare `use Boundary`.

**How to verify:** Grep changed files for `use Boundary`. Flag every match.

## Check 3: No reintroduced ports / DI wiring

**Rule:** Aggregate persistence has no port behaviour and no DI indirection.

**How to verify:**
1. Flag new files under `domain/ports/`
2. Flag new `@callback` behaviours named `For<Verb><Nouns>` wrapping persistence/CRUD
3. Flag new `Application.compile_env!(:klass_hero, [:<context>, :for_...])` DI reads and
   the matching `config :klass_hero, :<context>, for_...:` entries
4. Exception: `:shared, for_tracking_processed_events` is the one surviving key — not a violation

## Check 4: Cross-context access via facade

**Rule:** Code in context A reaches context B only through B's root module
`KlassHero.B` — called **directly**, at every layer (ADR 0015); an ACL adapter under
A's `acl/` (flat shape) or `adapters/driven/acl/` (old shape) is a valid wrapper but
not the expected one. Never alias B's internal schemas, entity modules, or Repo.

**How to verify:**
1. For each changed module, list `alias`/references that resolve to another context
2. Flag any that point at `KlassHero.B.<Internal>` (schemas, entity modules, adapters) rather than `KlassHero.B` itself
3. Exception: the Accounts `User` schema may be referenced for `belongs_to` associations

## Check 5: Survivor placement

**Rule:** Each surviving kind is identified by what it **is**, not by which tree its
context happens to use, and must sit in a location legal for that context's current
shape:

| Kind | Identify by | Legal locations |
|---|---|---|
| Projection GenServer | `use KlassHero.Shared.Projection` (or `.WithBootstrapRetry`) | `<context>/projections/` (3+ files), `<context>/<name>.ex` at root, or old `adapters/driven/projections/` |
| Oban worker | `use Oban.Worker` | `<context>/workers/` (3+ files), `<context>/<name>.ex` at root, or old `adapters/driving/workers/` |
| Event handler | consumes another context's events — registered as `{Module, :function}` under `:event_consumers` in `config/config.exs` | `<context>/<handler>.ex` at root, named for what it consumes (flat shape has no `events/` dir for these), or old `adapters/driving/events/` |
| ACL adapter | moduledoc/name signals anti-corruption-layer purpose (e.g. name ends `ACL`, or moduledoc states cross-context translation) | `<context>/acl/` (3+ files), `<context>/<name>.ex` at root, or old `adapters/driven/acl/` |
| Notification sender | sends email/notifications via a Shared adapter | `<context>/notifications/` (3+ files), `<context>/<name>.ex` at root, or old `adapters/driven/notifications/` |

A projection's **read table** goes the other way in *both* shapes: it lives at the
**context root** (`lib/klass_hero/<context>/<name>.ex`), beside the entities, never
under `adapters/`, `projections/`, or `persistence/`. It declares itself with
`use KlassHero.Shared.ReadTable` and carries **no changeset** — the projection is its
only writer.

**How to verify:**
1. Grep new `use Oban.Worker`, `use KlassHero.Shared.Projection`, and moduledocs naming
   an ACL — do this by signature across the whole diff, not by walking a fixed directory,
   so a flattened context's root-level modules aren't missed
2. For each match, confirm it sits in one of that kind's legal locations from the table above
3. Grep new `use KlassHero.Shared.ReadTable` — must be at a context root, and the module
   must define no `*changeset*` clause
4. Flag anything placed somewhere illegal under **both** shapes (e.g. filed under a
   nonstandard directory like `services/`, or a projection dropped loose at the root of a
   context whose projections already number 3+ elsewhere)

`mix lint_read_tables` gates rule 3 in CI, keyed off the same `use` line. If you find a
placement violation this check would catch, the gate should have caught it first — say so,
because that means the two have drifted.

## Check 6: Projection convention

**Rule:** Projections `use KlassHero.Shared.Projection` (optionally
`KlassHero.Shared.Projection.WithBootstrapRetry`), declare `:topics`, and implement
`bootstrap_impl/0` and `handle_event/2`.

**How to verify:**
1. Locate every projection GenServer by its `use KlassHero.Shared.Projection[, ...]`
   signature — this finds them under the flat `<context>/projections/` layout and the old
   `adapters/driven/projections/` tree alike
2. Confirm `use KlassHero.Shared.Projection, ...` with a `:topics` list
3. Confirm `bootstrap_impl/0` and `handle_event/2` are implemented
4. Reference: `lib/klass_hero/provider/projections/provider_session_details.ex`
   (most contexts have no projection — see the CQRS section of `domain-architecture.md`
   for why one now needs justifying)
5. Flag hand-rolled projection GenServers that bypass the macro

## Check 7: Read-model DTO purity

**Rule:** Read models are display-optimized structs over WRITE tables with no business
logic and no Ecto/Phoenix/Repo dependencies, wherever they're declared.

**How to verify:**
1. Locate candidates in `domain/read_models/` (old shape) and `read_models/` (flat shape,
   3+ files); below that threshold a flattened context's read models sit as ordinary
   `<name>.ex` files at the context root, so also check any new root-level module the diff
   introduces as a query-shaped struct over write tables
2. Confirm `defstruct` (not `use Ecto.Schema`) and no infra imports
3. Flag business logic or `KlassHero.Repo` usage

## Check 8: Event struct purity & placement

**Rule:** Event structs are pure (no Ecto/Phoenix/Repo/Oban), wherever they're declared.
Consumers are registered per topic under `:event_consumers` in `config/config.exs`.

**How to verify:**
1. Locate event structs in `domain/events/` (old shape — one file per struct) or in the
   single context-root `events.ex` factory (flat shape — one file holding all of that
   context's integration event structs)
2. Confirm pure struct definitions, no infra dependencies
3. If a new event is introduced, confirm a consumer is registered in `config/config.exs`
   under `:event_consumers`. That registry is also the staging filter — an unregistered
   event is silently dropped by `Outbox.stage/2` rather than delivered.

---

## Output Format

```
# Architecture Review Report

## Summary
- Checks passed: N/8
- Violations found: N
- Warnings: N

## Violations

### [CHECK_NAME] — [severity: error|warning]
- **File:** path/to/file.ex
- **Issue:** Description of what's wrong
- **Expected:** What the correct pattern should be
- **Fix:** Suggested remediation

## Passed Checks
- [list of checks that passed cleanly]
```

---

## Rules

- Run ALL 8 checks for every review — do not skip checks even if they seem irrelevant
- Both the flattened and old-DDD-derived shapes are legal simultaneously during the
  migration (see the note above `## Context`) — a context using the old tree is not itself
  a finding, and neither is a context missing `adapters/`/`domain/` because it's flat
- Severity: `error` for reintroduced-DDD structural violations (ports, DI, Boundary,
  domain/models split) and cross-context internal access; `warning` for placement/convention
- Always read the actual file content before flagging — do not rely on path inference alone
- The `Shared` context is special: it still holds `domain/models/`, `domain/ports/driving/`,
  and event infrastructure — do NOT flag Shared for these (they are the event/projection
  infra the flatten deliberately kept)
- `Accounts` uses `phx.gen.auth` — `user.ex` is the schema-as-struct
- `Admin` is lightweight (`queries.ex` for Backpex reads)
