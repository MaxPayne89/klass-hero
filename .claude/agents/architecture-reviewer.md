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

## Context

Bounded contexts under `lib/klass_hero/`:
Accounts, Family, Provider, ProgramCatalog, Enrollment, Messaging, Participation, Shared, Admin.

Current per-context layout:
```
context.ex                  # Public API — the ONLY module other contexts call
context/
├── <entity>.ex             # Schema-as-struct: Ecto schema + struct + functional core
│                           #   (validators, state machines). e.g. provider/staff_member.ex
├── <use_case>.ex           # Flat command/query modules at root (e.g. enrollment/claim_invite.ex)
│                           #   some contexts also use application/commands|queries/
├── domain/
│   ├── events/             # Domain & integration event structs (pure)
│   └── read_models/        # CQRS read-model DTOs (display structs, no logic)
└── adapters/
    ├── driven/{projections,persistence,acl,notifications}/
    └── driving/{events,workers}/
```

**Survivors** (legitimate subdirs): `adapters/driven/projections/` + `domain/read_models/`
(CQRS), `adapters/driven/persistence/` (projection read-tables only),
`adapters/driven/acl/` (cross-context reads), `adapters/driven/notifications/`,
`adapters/driving/events/`, `adapters/driving/workers/`, `domain/events/`.

**Removed** (flag if reintroduced): `domain/models/`, `domain/ports/`,
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
`KlassHero.B` (or an ACL adapter under A's `adapters/driven/acl/`). Never alias B's
internal schemas, entity modules, or Repo.

**How to verify:**
1. For each changed module, list `alias`/references that resolve to another context
2. Flag any that point at `KlassHero.B.<Internal>` (schemas, entity modules, adapters) rather than `KlassHero.B` itself
3. Exception: the Accounts `User` schema may be referenced for `belongs_to` associations

## Check 5: Survivor placement

**Rule:** The subdirectories that survived the flatten hold only their intended kinds:
- projections → `adapters/driven/projections/`
- ACL adapters → `adapters/driven/acl/`
- notifications → `adapters/driven/notifications/`
- event handlers → `adapters/driving/events/` (specific handlers in `events/event_handlers/`)
- Oban workers → `adapters/driving/workers/`

**How to verify:**
1. Grep new `use Oban.Worker` — must be in `adapters/driving/workers/`
2. New event handlers must be in `adapters/driving/events/**`
3. New projection GenServers must be in `adapters/driven/projections/`
4. Flag anything placed outside its directory

## Check 6: Projection convention

**Rule:** Projections `use KlassHero.Shared.Projection` (optionally
`KlassHero.Shared.Projection.WithBootstrapRetry`), declare `:topics`, and implement
`bootstrap_impl/0` and `handle_event/2`.

**How to verify:**
1. For each file in `adapters/driven/projections/`
2. Confirm `use KlassHero.Shared.Projection, ...` with a `:topics` list
3. Confirm `bootstrap_impl/0` and `handle_event/2` are implemented
4. Reference: `lib/klass_hero/provider/adapters/driven/projections/provider_programs.ex`
5. Flag hand-rolled projection GenServers that bypass the macro

## Check 7: Read-model DTO purity

**Rule:** Read models in `domain/read_models/` are display-optimized structs with no
business logic and no Ecto/Phoenix/Repo dependencies.

**How to verify:**
1. For each file in `domain/read_models/`
2. Confirm `defstruct` (not `use Ecto.Schema`) and no infra imports
3. Flag business logic or `KlassHero.Repo` usage

## Check 8: Event struct purity & placement

**Rule:** Event structs live in `domain/events/` and are pure (no Ecto/Phoenix/Repo/Oban).
Consumers are registered per topic under `:event_consumers` in `config/config.exs`.

**How to verify:**
1. For each file in `domain/events/`
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
- Severity: `error` for reintroduced-DDD structural violations (ports, DI, Boundary,
  domain/models split) and cross-context internal access; `warning` for placement/convention
- Always read the actual file content before flagging — do not rely on path inference alone
- The `Shared` context is special: it still holds `domain/models/`, `domain/ports/driving/`,
  and event infrastructure — do NOT flag Shared for these (they are the event/projection
  infra the flatten deliberately kept)
- `Accounts` uses `phx.gen.auth` — `user.ex` is the schema-as-struct
- `Admin` is lightweight (`queries.ex` for Backpex reads)
