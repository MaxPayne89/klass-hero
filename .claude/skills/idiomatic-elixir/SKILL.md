---
name: idiomatic-elixir
description: Elixir idioms for writing clean, functional, and domain-driven code. ALWAYS use this skill when writing, modifying, reviewing, or refactoring any Elixir (.ex) or Elixir script (.exs) file. Also trigger when working in any Elixir/Phoenix project, designing modules or contexts, implementing OTP patterns, writing tests, or creating migrations. This skill covers pattern matching, pipes, error handling, DDD with structs and contexts, OTP patterns, and modern Elixir 1.17–1.20 features including the type system, Duration, built-in JSON, and parameterized tests.
---

# Idiomatic Elixir for Domain-Driven Design

> **TL;DR:** Pattern match everything, pipe data through functions, use `with` for error handling, model domains with structs and contexts. Return `{:ok, result}` or `{:error, reason}` — never naked `nil`. Let unexpected errors crash; supervisors handle recovery. Leverage the compiler type system — write clear patterns and guards, skip redundant runtime checks.

## Instructions

Apply these idioms when writing Elixir to produce clean, functional, and domain-driven code. These patterns leverage Elixir's language features and OTP to build maintainable systems that model business domains effectively.

**Code examples:** See `examples.md` in this directory.
**Modern Elixir (1.17–1.20):** See `references/modern-elixir.md` for new language features.
**Deprecations:** See `references/deprecations.md` for patterns to avoid.

---

## Essentials

Core patterns every Elixir developer should internalize first.

---

## Pattern 1: Pattern Matching — Multi-Clause Functions

- Eliminates conditional branching with declarative dispatch
- Self-documenting function behavior based on input shape
- Enables exhaustive case handling at compile time
- Natural fit for modeling domain state transitions

**Key principle:** Prefer multiple function clauses over `if/case` inside a single function. Let the pattern declare intent.

---

## Pattern 2: Pipe Operator — Data Transformation Pipelines

- Creates readable left-to-right data flow
- Eliminates nested function calls
- Makes transformation steps explicit

**Key principle:** Structure functions to accept the "subject" as the first argument. Break long pipelines into named private functions.

---

## Pattern 3: With Statement — Railway-Oriented Error Handling

- Chains operations that may fail without nested case statements
- Short-circuits on first error with clean else handling
- Perfect for multi-step domain operations

**Key principle:** Use `with` for operations with multiple potential failure points. Keep the happy path in the main clause, errors in `else`.

---

## Pattern 4: Structs — Domain Entity Modeling

- Enforces required fields at compile time via `@enforce_keys`
- Provides meaningful names for domain concepts
- Enables pattern matching on type
- Maps directly to DDD entities and value objects

**Key principle:** Use structs for any domain concept with identity (entity) or defined by attributes (value object). Never use bare maps for domain models.

---

## Intermediate

Domain modeling patterns for Phoenix applications and DDD.

---

## Pattern 5: Protocols — Polymorphism via Contracts

- Enables polymorphic behavior without inheritance
- Allows extending types you don't own
- Models DDD interfaces and polymorphic domain behaviors

**Key principle:** Use protocols when different domain types need the same operation but different implementations. Think "Printable", "Serializable", "Priceable".

**Note (1.19+):** The type system now checks protocol dispatch — passing a type that doesn't implement the protocol produces a compile-time warning.

---

## Pattern 6: Behaviours — Callback Contracts for Modules

- Defines explicit contracts that modules must implement
- Compile-time verification of implementations
- Good for genuinely swappable implementations (feature-flag adapters, external service clients)

**Key principle:** Use behaviours only where implementations are actually interchangeable. This codebase flattened away aggregate persistence ports (#986–#1002) — do NOT introduce a behaviour just to wrap `Repo`. Protocols for data, behaviours for modules.

---

## Pattern 7: Bounded Contexts — Phoenix Contexts

- Separates domain concerns into cohesive modules
- Provides clear public APIs for each domain area
- Prevents cross-domain coupling
- Aligns directly with DDD bounded contexts

**Key principle:** Each context owns its data and logic. Other contexts communicate through the public API, never reaching into internals.

---

## Pattern 8: Aggregates with Structs — Root Entities

- Encapsulates related entities under a single root
- Ensures consistency boundaries
- Simplifies persistence and retrieval

**Key principle:** External code never modifies nested entities directly. The aggregate root enforces all invariants.

---

## Pattern 9: Changesets — Domain Validation

- Separates validation from data structures
- Accumulates multiple errors
- Supports context-specific validation (create vs update)

**Key principle:** Validate at the boundary. Changesets are the gatekeepers ensuring only valid data enters your domain.

---

## Pattern 10: Functional Core, Imperative Shell

- Pure functions are easier to test and reason about
- Side effects isolated to outer layers
- Domain logic remains framework-agnostic

**Key principle:** The core computes, the shell acts. Test the core exhaustively with unit tests, the shell with integration tests.

---

## Pattern 11: Schema-as-Struct — Data Access via the Context Module

- One module per entity is the Ecto schema, the struct callers match on, and the functional core (validators, state machines) — no separate domain model, mapper, or repository
- The context module (`<context>.ex`) is the public data-access API and calls `Repo` directly; no port/behaviour wraps persistence
- Fewer files and less indirection, at the deliberate cost of swappable storage (a trade this project decided it doesn't need)

**Key principle:** New query and persistence code goes in the context module (`<context>.ex`), and new validation goes in the entity's changesets — not in a repository or port layer. Canonical example: `lib/klass_hero/provider/staff_member.ex`. Persistence subdirectories (`adapters/driven/persistence/`) are reserved for CQRS projection read-tables only.


---

## Advanced / OTP

Concurrency patterns and advanced functional idioms.

---

## Pattern 12: GenServer — Stateful Domain Services

- Manages state across requests
- Serializes access to shared resources
- Use `Process.set_label/1` (1.17+) for debugging visibility

**Key principle:** Only use GenServer when you need state or serialization. Pure functions are simpler when state isn't required.

---

## Pattern 13: Supervisors — Fault-Tolerant Process Trees

- Automatic restart of failed processes
- Isolation of failures
- Declarative process lifecycle management

**Key principle:** Design for failure. Structure supervision trees so failures in one area don't cascade to others.

---

## Pattern 14: Let It Crash — Offensive Error Handling

- Simplifies code by not handling unlikely errors inline
- Leverages supervision for recovery
- Distinguishes expected errors from bugs

**Key principle:** Pattern match on expected outcomes. Crashes from unexpected states are bugs to fix, not errors to handle.

---

## Pattern 15: Tagged Tuples — Result Convention

- Explicit success/failure signaling
- Composable with `with` and pipelines

**Key principle:** Functions that can fail return tagged tuples. Use the bang (`!`) suffix for raising variants. Never return naked `nil` for errors.

---

## Pattern 16: Reduce/Fold — Accumulator Transformations

- Handles complex transformations functionally
- Single pass over collections
- Powerful for aggregations and state building

**Key principle:** When `map` or `filter` won't suffice, reach for `reduce`. For simple sums, prefer `Enum.sum_by/2` (1.18+).

---

## Pattern 17: Comprehensions — Declarative Generation

- Combines filtering and mapping concisely
- Supports multiple generators and filters
- Can collect into different types via `:into`

**Key principle:** Use comprehensions for cartesian products, nested iterations, or when you need both filter and map.

---

## Pattern 18: Keyword Lists & Options — Flexible Parameters

- Clean optional parameter handling
- Self-documenting option names with defaults

**Key principle:** Use keyword lists for options, not positional arguments. Document available options in `@doc`.

---

## Pattern 19: Type-Aware Code (1.17+)

The compiler has a gradual set-theoretic type system that infers types from patterns, guards, and function calls. By 1.20, full function-level inference is active.

**How to leverage it:**
- Write clear pattern matches and guards — the compiler propagates type information
- Use `Map.fetch!/2` over `Map.get/2` when a key must exist — helps type system track key presence
- Use `is_non_struct_map/1` guard (1.17+) to distinguish maps from structs
- Reduce defensive runtime type checks where the compiler already verifies correctness
- Bang functions and explicit pattern matches give the type system more information to work with

**Key principle:** Trust the compiler. Write precise patterns and guards; the type system rewards clarity with better error detection.

---

## Modern Elixir Quick Reference

For detailed coverage of 1.17–1.20 features, see `references/modern-elixir.md`. Highlights:

- **`Duration` + `to_timeout/1`** — calendar-aware shifts, timeout normalization
- **Built-in `JSON` module** (1.18+) — `JSON.encode!/1`, `JSON.decode!/1`, `@derive {JSON.Encoder, only: [...]}`
- **`Enum.sum_by/2`, `Enum.product_by/2`** (1.18+) — replace `Enum.map |> Enum.sum` patterns
- **Parameterized ExUnit tests** (1.18+) — test multiple configurations concurrently
- **`Process.set_label/1`** (1.17+) — label processes for debugging
- **`min/2`, `max/2` as guards** (1.19+)
- **`mix format --migrate`** — auto-converts deprecated syntax

---

## Best Practices Summary

1. **Pattern match everywhere** — let function clauses declare intent
2. **Pipe for transformations** — left-to-right data flow
3. **With for fallible chains** — keep happy path linear
4. **Structs for domain models** — never bare maps for entities
5. **Protocols for polymorphism** — extend without inheritance
6. **Behaviours for contracts** — compile-time interface verification
7. **Contexts as bounded contexts** — DDD alignment built-in
8. **Aggregates for consistency** — root entities own their children
9. **Changesets at boundaries** — validate once, trust internally
10. **Functional core** — pure logic, impure shell
11. **Contexts as repositories** — abstract data access
12. **GenServer for state** — not for everything
13. **Supervision for resilience** — design for failure
14. **Let it crash** — handle expected, crash on unexpected
15. **Tagged tuples always** — explicit success/failure
16. **Reduce for complex transforms** — the universal iterator
17. **Comprehensions for generation** — filter + map in one
18. **Keyword lists for options** — clean optional parameters
19. **Trust the type system** — precise patterns over defensive checks

## Common Pitfalls to Avoid

- Using bare maps instead of structs for domain entities
- Overusing `if/cond` when pattern matching is clearer
- Deeply nested `case` statements instead of `with`
- Not using `@enforce_keys` for required struct fields
- Implementing protocols when behaviours are more appropriate
- Putting business logic in controllers instead of contexts
- Modifying aggregate children directly, bypassing the root
- Validating data deep inside the domain instead of at boundaries
- Mixing IO and side effects into domain logic functions
- Using GenServer when a simple module with functions suffices
- Not defining supervision strategies for production processes
- Catching all errors instead of letting supervisors handle crashes
- Returning `nil` instead of `{:error, reason}` for failures
- Using `Enum.map` + `Enum.filter` when `for` comprehension is cleaner
- Positional arguments for optional parameters instead of keyword lists
- Ignoring the bang (`!`) suffix convention for raising functions
- Using `unless` — prefer `if !condition do` (soft-deprecated 1.18)
- Using single-quoted charlists `'foo'` — use `~c"foo"` sigil
- Manual millisecond math for timeouts — use `to_timeout/1`
- `Enum.map(items, &field/1) |> Enum.sum()` — use `Enum.sum_by/2`
