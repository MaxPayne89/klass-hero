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
2. Wrap that facade call in an ACL adapter under A's `adapters/driven/acl/` **only
   when the adapter earns its place** by doing genuine translation: remapping B's
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
3. Flag references that resolve to another context's internals
   (`KlassHero.B.<Entity>`, `KlassHero.B.Adapters.*`, `KlassHero.B.<...>Schema`)
   rather than `KlassHero.B` itself
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

**How to verify:**
1. For each changed module, extract schema modules referenced in queries
   (`from`, `join`, `preload`) and any `Repo` calls
2. Determine each schema's owning context
3. Flag references to another context's schemas/tables (except the allowed exception)
4. Do NOT flag a context using `Repo` on its own schemas — that is the convention now

## Check 3: Event handlers must use facade APIs

**Rule:** Event handlers in `adapters/driving/events/` that act on another context
must call that context's root facade — not its internal entity, query, or adapter
modules.

**How to verify:**
1. For each event handler, extract calls that reach into another context
2. Calls should be to `KlassHero.<Context>.function_name()` (facade)
3. Flag calls to `KlassHero.<Context>.Adapters.*` or internal entity modules
4. Within-context handlers MAY call their own context's internals directly

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

**Rule:** `domain/events/` and `domain/read_models/` must be pure — ZERO
dependencies on Ecto (`Ecto.Changeset/Schema/Query`), Phoenix, infrastructure
(`KlassHero.Repo`, `Oban`, `Jason`), or other contexts' internals.

**How to verify:**
1. For each file in `domain/events/`, `domain/read_models/`
2. Extract `alias`/`import`/`use`/`require` declarations
3. Allow: own context's domain modules, Elixir/Erlang stdlib,
   `KlassHero.Shared.Domain.*`, `Logger`
4. Flag any infrastructure or cross-context dependency

## Check 5: ACL adapter correctness

**Rule:** Anti-Corruption Layer adapters (`adapters/driven/acl/`) must:
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
- The `Accounts.User` reference is a KNOWN exception — do not flag it
- Shared (`KlassHero.Shared.*`) is universal infrastructure — accessible to all
- A context using `Repo` on its OWN schemas is correct (schema-as-struct) — never flag it
- A direct facade call is the DEFAULT for a cross-context read (ADR 0015) — never flag one
  for lacking an ACL. Reserve a projection for a genuinely hot read path
- Critical severity: cross-context Repo/schema access, reaching into another context's internals
- Warning severity: cross-context `belongs_to` beyond the User exception, an unnecessary ACL
  (pure delegation — no error remapping, no business-rule masking, no cycle to break)
