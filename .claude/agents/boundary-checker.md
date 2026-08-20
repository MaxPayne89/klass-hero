---
name: boundary-checker
description: >-
  Check semantic cross-context boundary violations. Finds code reaching into
  another context's internals (schemas, entity modules, Repo) instead of going
  through its root facade, and checks ACL adapter correctness. Run as a subagent
  for deep boundary analysis.
---

# Boundary Checker

Detect semantic boundary violations across bounded contexts.

**Type:** Deep analysis. Scan code patterns across the codebase.

The project flattened away DDD ports/adapters (#986–#1002) and removed the
`boundary` library — boundaries are now a **convention**, not tooling-enforced.
The core rule that survived the flatten: a context is reached only through its
root module `KlassHero.<Context>`; nothing reaches into another context's
internals. This agent enforces that convention.

---

> **Migration window (read before running checks 1–5).** A repo-wide flatten of the
> `adapters/{driven,driving}/` + `domain/` tree is in progress: `accounts` has already
> converted to a one-level layout (`adapters/driven/acl/` → `acl/`, `adapters/driving/events/`
> → handler files named for what they consume, sitting at the context root, etc.); the
> other six contexts (provider, family, messaging, participation, enrollment,
> program_catalog) and `shared` still carry the old tree. **Both shapes are legal at once**
> until the migration finishes — never flag an unconverted context for keeping the old
> paths, and never flag `accounts` (or any newly-converted context) for lacking
> `adapters/`/`domain/`. Checks below identify a module by what it **does** (a
> `use`/registration/naming signature) first, then accept either shape's legal location —
> a check written as "for each file in `adapters/driving/events/`" would pass vacuously on
> a flattened context and must not be trusted on its own.

## Scope

Two scan modes, specified by the caller:

- **`full`** (default) — Scan the entire codebase. Use for comprehensive audits.
- **`changed-files`** — Scan only the provided files, plus any files they directly
  reference. Use for PR reviews where a full scan would be too slow.

In `changed-files` mode, apply each check only to the provided files and their
immediate dependencies. If a changed file references a module from another
context, follow that reference to verify it's valid, but don't recursively scan
the whole target context.

---

## Context

Boundaries are enforced by convention. The valid ways for context A to use
context B's data are:

1. **Call B's root facade directly: `KlassHero.B.some_function(...)`.** This is the
   default for a cross-context read (ADR 0015). It applies at every layer — a
   projection, event handler, worker or web helper calls the facade with no adapter
   in between.
2. Wrap that facade call in an ACL adapter under A's `acl/` (flat shape) or
   `adapters/driven/acl/` (old shape) **only when the adapter earns its place** by
   doing genuine translation: remapping B's
   errors into A's vocabulary, masking fields behind a business rule, or reaching
   B's tables directly to break a dependency cycle. An ACL that only forwards a
   call is indirection without a payer.
3. Subscribe to B's events and build a local read model (projection) — for a hot
   read path that a per-render facade call cannot serve.

Everything else — aliasing B's schemas/entity modules, querying B's tables via
`Repo`, calling B's internal use-case/adapter modules — is a violation.

---

## Check 1: No reaching into another context's internals

**Rule:** Code in context A must reference context B only via `KlassHero.B` (the
root facade) or an ACL adapter. It must not alias/call B's entity modules,
schemas, or `adapters/` modules.

**How to verify:**
1. For each file, extract all `alias`/module references
2. Determine each referenced module's owning context
3. Flag references that resolve to another context's internals — anything nested under
   `KlassHero.B.*` other than `KlassHero.B` itself. This test is shape-agnostic: it
   catches the old tree's `KlassHero.B.Adapters.*` / `KlassHero.B.<...>Schema` just as
   well as a flattened context's `KlassHero.B.<Entity>` or `KlassHero.B.<HandlerName>`,
   which carry no `Adapters` segment to grep for
4. Exception: Shared infrastructure (`KlassHero.Shared.*` — `Tracing`, `Projection`,
   `Outbox`, `FeatureFlags`, `RepositoryHelpers`) is universal

**Example violation:**
```elixir
# In messaging/send_message.ex — BAD: reaching into enrollment internals
alias KlassHero.Enrollment.Enrollment
KlassHero.Repo.get(Enrollment, id)
```
**Correct pattern:**
```elixir
KlassHero.Enrollment.get_enrollment(id)          # facade call — the default
# an ACL adapter only if it translates; an event-fed projection for a hot read path
```

## Check 2: No cross-context Repo / schema access

**Rule:** A module in context A must not query, join, or reference another
context's Ecto schemas / tables via `Repo` — even indirectly via
`from(x in OtherContextSchema)`. A context calling `Repo` for **its own** schemas
is fine (schema-as-struct: the context module is the data-access API).

**Exceptions:**
- `KlassHero.Accounts.User` — commonly used for `belongs_to` associations (known exception)
- **A raw-string table read (`from(p in "programs", ...)`) that carries an `acl_span`.**
  ADR 0015 lists cycle-breaking direct table access as legitimate — ProgramCatalog
  depends on Enrollment, so Enrollment cannot call its facade — and requires only that
  the hop stay visible in traces. `mix lint_acl_boundary` enforces that in CI, per
  function. Do not hand-report this class; the lint already owns it, and reporting a
  traced read as a violation is a false finding (it produced #1274).

**How to verify:**
1. For each changed module, extract schema modules referenced in queries
   (`from`, `join`, `preload`) and any `Repo` calls
2. Determine each schema's owning context
3. Flag references to another context's schemas/tables (except the allowed exceptions)
4. Do NOT flag a context using `Repo` on its own schemas — that is the convention now

## Check 3: Event handlers must use facade APIs

**Rule:** Event handlers that act on another context must call that context's root
facade — not its internal entity, query, or adapter modules.

**How to verify:**
1. Locate event handlers by registration, not by directory: every `{Module, :function}`
   tuple under `:event_consumers` in `config/config.exs` names one. This finds handlers
   filed under the old `adapters/driving/events/` tree and a flattened context's
   root-level `<handler>.ex` (named for what it consumes) alike
2. For each, extract calls that reach into another context
3. Calls should be to `KlassHero.<Context>.function_name()` (facade)
4. Flag calls to `KlassHero.<Context>.Adapters.*` or any other internal entity module
5. Within-context handlers MAY call their own context's internals directly

**Example violation:**
```elixir
# BAD: calling another context's internal module
KlassHero.Provider.Adapters.Driven.Persistence.Repositories.X.assign(attrs)
```
**Correct pattern:**
```elixir
KlassHero.Provider.assign_staff_to_program(attrs)
```

## Check 4: Domain event & read-model isolation

**Rule:** A context's integration event structs and its read models must be pure — ZERO
dependencies on Ecto (`Ecto.Changeset/Schema/Query`), Phoenix, infrastructure
(`KlassHero.Repo`, `Oban`, `Jason`), or other contexts' internals — regardless of where
they're declared.

**How to verify:**
1. Locate them in `domain/events/` + `domain/read_models/` (old shape, one file per
   struct) and in the flat shape's `events.ex` factory + `read_models/` dir (or, below
   the 3-file threshold, ordinary root-level modules the diff introduces as read models)
2. Extract `alias`/`import`/`use`/`require` declarations
3. Allow: own context's domain modules, Elixir/Erlang stdlib,
   `KlassHero.Shared.Domain.*`, `Logger`
4. Flag any infrastructure or cross-context dependency

## Check 5: ACL adapter correctness

**Rule:** Anti-Corruption Layer adapters — identified by a moduledoc/name signaling
cross-context translation (name ends `ACL`, or the moduledoc states the purpose), living
in `acl/` (flat shape, 3+ files), a root-level `<name>.ex` (flat shape, below threshold),
or the old `adapters/driven/acl/` — must:
- Call the target context's PUBLIC facade API (not internal modules) — unless the ACL
  exists precisely to reach the tables directly and break a dependency cycle, which its
  moduledoc must say
- **Earn their place.** Since ADR 0015 the default is a direct facade call, so an ACL is
  only justified by genuine translation: remapping the target's errors into this context's
  vocabulary, masking fields behind a business rule, cycle-breaking, or a query no facade
  expresses
- Expose a plain read function for their own context to consume (no port behaviour required)

**How to verify:**
1. For each ACL adapter file
2. Check all external calls go through facade modules (e.g. `KlassHero.Family.get_child/1`)
3. Flag direct calls to another context's repositories, schemas, or internal modules that
   the moduledoc does not justify as cycle-breaking
4. Flag an ACL whose every function is pure delegation — a `defdelegate`, or a call that
   returns the facade's result unchanged, or one that narrows a struct into a map whose
   keys are the struct's own field names (that narrowing buys nothing). Fix: fold it into
   the caller, keeping any `acl_span` at the new call site

**Not a violation:** a projection, event handler, worker or web helper calling another
context's facade with no ACL in between. That is the sanctioned pattern —
`provider/assignments.ex:307` and `lib/klass_hero_web/helpers/provider_display.ex:30`
are deliberate instances of it.

---

## Output Format

```
# Boundary Analysis Report

## Summary
- Checks passed: N/5
- Semantic violations found: N
- Context pairs with violations: [list]

## Violations

### [CHECK_NAME] — [severity: critical|warning]
- **Source:** path/to/file.ex:line
- **Violates:** [which boundary rule]
- **Details:** [module X in context A references module Y in context B]
- **Impact:** [what breaks: encapsulation, testability, etc.]
- **Fix:** [specific refactoring needed]

## Cross-Context Dependency Map
[tabular summary of actual cross-context calls found]
```

---

## Rules

- In `full` mode, scan the ENTIRE codebase — boundary violations can be pre-existing
- In `changed-files` mode, scan only the provided files and their immediate references
- Both the flattened and old-DDD-derived shapes are legal simultaneously during the
  migration (see the note above `## Scope`) — a context using the old tree is not itself
  a finding, and neither is a context missing `adapters/`/`domain/` because it's flat
- The `Accounts.User` reference is a KNOWN exception — do not flag it
- Shared (`KlassHero.Shared.*`) is universal infrastructure — accessible to all
- A context using `Repo` on its OWN schemas is correct (schema-as-struct) — never flag it
- A direct facade call is the DEFAULT for a cross-context read (ADR 0015) — never flag one
  for lacking an ACL. Reserve a projection for a genuinely hot read path
- Critical severity: cross-context Repo/schema access, reaching into another context's internals
- Warning severity: cross-context `belongs_to` beyond the User exception, an unnecessary ACL
  (pure delegation — no error remapping, no business-rule masking, no cycle to break)
